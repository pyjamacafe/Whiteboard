import { describe, expect, it } from 'vitest';
import {
  boundingBox,
  constrainShapeEnd,
  eraseStrokes,
  fillContainsPoint,
  imageRotatedCorners,
  pointInPolygon,
  recognizeShape,
  resizedRect,
  shapeContainsPoint,
  simplifyRDP,
  smoothCatmullRom,
  snapRotationAngle,
  SpatialHashGrid,
  textLabelCenter,
  textLabelContainsPoint,
  textLabelSize,
} from '../engine/geometry';
import { computeFillContours } from '../engine/floodFill';
import { CanvasHistory } from '../engine/history';
import { parseMarkdown, toggleMarkdownWrap } from '../engine/markdown';
import { decodeWBJson, encodeWBJson } from '../engine/wbCodec';
import { exportCanvasPDFBytes, exportScenesPDFBytes } from '../engine/pdfExport';
import { BoardStore } from '../store/boardStore';
import { DrawingStore } from '../store/drawingStore';
import {
  DEFAULT_LIGHT_PRESETS,
  generateId,
  type CanvasShape,
  type FillShape,
  type PlacedImage,
  type Point,
  type Stroke,
  type TextLabel,
} from '../types/model';

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

  it('produces Catmull-Rom cubic control points and preserves sharp corners & endpoints', () => {
    const pts = [
      { x: 0, y: 0 },
      { x: 10, y: 5 },
      { x: 20, y: 0 },
      { x: 30, y: 5 },
    ];
    const smooth = smoothCatmullRom(pts);
    expect(smooth.length).toBe(1 + (pts.length - 1) * 3);
    expect(smooth[0]).toEqual(pts[0]);
    expect(smooth[smooth.length - 1]).toEqual(pts[pts.length - 1]);

    // Crisp 90-degree L-corner must not be melted/rounded off
    const cornerPts = [
      { x: 0, y: 0 },
      { x: 50, y: 0 },
      { x: 50, y: 50 },
    ];
    const cornerSmooth = smoothCatmullRom(cornerPts);
    // Vertex index 1 sits at result[3]
    expect(cornerSmooth[3].x).toBeCloseTo(50, 4);
    expect(cornerSmooth[3].y).toBeCloseTo(0, 4);
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

describe('DrawingStore Phase 2 (Lasso, Rotation Handle, Images, Scenes)', () => {
  it('supports tap-to-select for Pen, Sharpie, Fill, and clearLassoSelection', () => {
    const store = new DrawingStore(false);
    const pen = makeStroke(
      [
        { x: 0, y: 0 },
        { x: 80, y: 0 },
      ],
      { isSharpie: false }
    );
    const sharpie = makeStroke(
      [
        { x: 0, y: 100 },
        { x: 80, y: 100 },
      ],
      { isSharpie: true }
    );
    const fill: FillShape = {
      id: generateId(),
      contours: [
        [
          { x: 200, y: 0 },
          { x: 280, y: 0 },
          { x: 280, y: 80 },
          { x: 200, y: 80 },
        ],
      ],
      color: { r: 0, g: 0.35, b: 1, a: 1 },
      opacity: 0.5,
      presetIndex: 5,
    };
    store.loadSaveData({ strokes: [pen, sharpie], fills: [fill], placedImages: [], scenes: [] });
    store.selectTool('select');

    // Tap pen via beginLasso + endLasso
    store.beginLasso({ x: 40, y: 2 });
    store.endLasso(1);
    expect(store.getSnapshot().selectedStrokeIds).toEqual([pen.id]);
    expect(store.getSnapshot().selectionBoundary.length).toBeGreaterThan(0);

    // Tap sharpie
    expect(store.selectElement({ x: 40, y: 100 }, 1)).toBe(true);
    expect(store.getSnapshot().selectedStrokeIds).toEqual([sharpie.id]);

    // Tap fill
    expect(store.selectElement({ x: 240, y: 40 }, 1)).toBe(true);
    expect(store.getSnapshot().selectedFillIds).toEqual([fill.id]);

    // Esc / clearLassoSelection stays in select tool
    store.clearLassoSelection();
    expect(store.getSnapshot().currentTool).toBe('select');
    expect(store.hasAnySelectionOrLasso).toBe(false);

    // Empty lasso leaves no stale boundary
    store.beginLasso({ x: 450, y: 450 });
    store.addLassoPoint({ x: 550, y: 450 });
    store.addLassoPoint({ x: 550, y: 550 });
    store.addLassoPoint({ x: 450, y: 550 });
    store.endLasso(1);
    expect(store.getSnapshot().selectionBoundary).toEqual([]);
  });

  it('rotates strokes and placed images via handle, supports single undo and reset', () => {
    const store = new DrawingStore(false);
    const s = makeStroke([
      { x: 0, y: 0 },
      { x: 100, y: 0 },
    ]);
    store.loadSaveData({ strokes: [s], fills: [], placedImages: [], scenes: [] });
    store.selectTool('select');
    store.selectElement({ x: 50, y: 0 }, 1);
    expect(store.canResetSelectionRotation).toBe(false);

    const geom = store.rotationHandleGeometry(1)!;
    expect(geom).not.toBeNull();
    expect(store.hitTestRotateHandle(geom.handleCenter, 1)).toBe(true);

    // Drag 90° clockwise
    store.beginRotate(geom.handleCenter, 1);
    store.updateRotate({ x: geom.pivot.x + 15, y: geom.pivot.y - 25 }, false);
    store.updateRotate({ x: geom.pivot.x + 28, y: geom.pivot.y }, false);
    store.commitRotate();

    expect(store.canResetSelectionRotation).toBe(true);
    expect(store.activeRotationLabel).toBe('90°');
    const rotated = store.getSnapshot().strokes[0].points;
    expect(rotated[0].x).toBeCloseTo(50, 0);
    expect(rotated[0].y).toBeCloseTo(-50, 0);

    // Reset Rotation
    store.resetSelectionRotation();
    expect(store.canResetSelectionRotation).toBe(false);
    expect(store.getSnapshot().strokes[0].points[0].x).toBeCloseTo(0, 0);

    // PlacedImage rotation persists across re-select
    store.addImageFromDataUrl('data:image/png;base64,AQID', 80, 40, 0, { x: 300, y: 300 });
    const imgGeom = store.rotationHandleGeometry(1)!;
    store.beginRotate(imgGeom.handleCenter, 1);
    store.updateRotate({ x: imgGeom.pivot.x + 40, y: imgGeom.pivot.y - 40 }, true);
    store.commitRotate();
    expect(store.getSnapshot().placedImages[0].rotation).toBeCloseTo(Math.PI / 4, 4);

    store.clearSelection();
    store.selectElement({ x: 300, y: 300 }, 1);
    expect(store.canResetSelectionRotation).toBe(true);
    expect(store.activeRotationLabel).toBe('45°');
    store.resetSelectionRotation();
    expect(store.getSnapshot().placedImages[0].rotation).toBeCloseTo(0, 5);
  });

  it('supports Scenes CRUD, reorder, and navigation', () => {
    const store = new DrawingStore(false);
    store.reportViewport({ x: 10, y: 20 }, 1.2);
    const s1 = store.addScene('Intro');
    store.reportViewport({ x: 300, y: 400 }, 2.0);
    const s2 = store.addScene('Diagram');

    expect(store.getSnapshot().scenes.length).toBe(2);
    store.renameScene(s1.id, 'Overview');
    expect(store.getSnapshot().scenes[0].name).toBe('Overview');
    store.moveScene(0, 1);
    expect(store.getSnapshot().scenes[0].id).toBe(s2.id);

    store.goToNextScene();
    expect(store.getSnapshot().activeSceneId).toBe(s1.id);
    store.deleteScene(s1.id);
    expect(store.getSnapshot().scenes.length).toBe(1);
  });

  it('captures actual initial viewport center for default Scene 1', () => {
    const store = new DrawingStore(false);
    const defaultScene = { id: generateId(), name: 'Scene 1', centerX: 0, centerY: 0, scale: 1 };
    store.loadSaveData({ strokes: [], fills: [], placedImages: [], shapes: [], textLabels: [], scenes: [defaultScene] });
    store.requestDefaultSceneCapture();
    store.reportViewport({ x: 720, y: 450 }, 1);

    expect(store.getSnapshot().scenes[0].centerX).toBe(720);
    expect(store.getSnapshot().scenes[0].centerY).toBe(450);
    expect(store.getSnapshot().scenes[0].scale).toBe(1);

    // Subsequent panning must NOT overwrite Scene 1
    store.reportViewport({ x: 1500, y: 1200 }, 1);
    expect(store.getSnapshot().scenes[0].centerX).toBe(720);
    expect(store.getSnapshot().scenes[0].centerY).toBe(450);
  });
});

describe('Phase 3 (BoardStore Trash/Restore & Vector PDF Export)', () => {
  it('persists boards, folders, thumbnails, and 30-day trash restore/purge', async () => {
    const bs = new BoardStore(true);
    const s = makeStroke([
      { x: 0, y: 0 },
      { x: 50, y: 50 },
    ]);
    await bs.saveBoard('b1', { strokes: [s], fills: [], placedImages: [], scenes: [] });
    await bs.saveIndex({
      boards: [{ id: 'b1', name: 'Napkin 1', created: 1000, modified: 2000, isPinned: true }],
      folders: [{ id: 'f1', name: 'Work', boardIds: ['b1'] }],
    });

    const idx = await bs.loadIndex();
    expect(idx.boards[0].isPinned).toBe(true);
    expect(idx.folders[0].name).toBe('Work');

    const now = Date.now();
    const trash = await bs.trashBoard('b1', 'Napkin 1', now);
    expect(trash.length).toBe(1);
    expect(await bs.loadBoard('b1')).toBeNull();

    const restored = await bs.restoreBoard('b1', 'b2');
    expect(restored?.name).toBe('Napkin 1');
    expect(restored?.data.strokes.length).toBe(1);
    expect((await bs.loadBoard('b2'))?.strokes.length).toBe(1);
    expect((await bs.loadTrash()).length).toBe(0);

    // Entries older than 30 days are auto-purged
    await bs.trashBoard('old', 'Ancient', now - 31 * 24 * 3600 * 1000);
    expect((await bs.loadTrash(now)).length).toBe(0);
  });

  it('exports valid vector PDF for single canvas and multi-page scenes', async () => {
    const s = makeStroke([
      { x: 0, y: 0 },
      { x: 100, y: 50 },
      { x: 200, y: 10 },
    ]);
    const pdfBytes = await exportCanvasPDFBytes({
      strokes: [s],
      fills: [],
      placedImages: [],
      penPresets: DEFAULT_LIGHT_PRESETS,
      sharpiePresets: DEFAULT_LIGHT_PRESETS,
      fillPresets: DEFAULT_LIGHT_PRESETS,
      isDarkMode: false,
      isWarmPaper: true,
    });
    expect(pdfBytes).not.toBeNull();
    expect(new TextDecoder().decode(pdfBytes!.slice(0, 5))).toBe('%PDF-');

    const deckBytes = await exportScenesPDFBytes({
      scenes: [
        { id: generateId(), name: 'Slide 1', centerX: 50, centerY: 25, scale: 1 },
        { id: generateId(), name: 'Slide 2', centerX: 150, centerY: 25, scale: 1.5 },
      ],
      strokes: [s],
      fills: [],
      placedImages: [],
      penPresets: DEFAULT_LIGHT_PRESETS,
      sharpiePresets: DEFAULT_LIGHT_PRESETS,
      fillPresets: DEFAULT_LIGHT_PRESETS,
      isDarkMode: true,
      isWarmPaper: false,
    });
    expect(deckBytes).not.toBeNull();
    expect(deckBytes!.length).toBeGreaterThan(300);
  });
});

describe('Shapes & TextLabels Phase 1 (Geometry, FloodFill, .wb Codec)', () => {
  it('hit-tests shapes/text, constrains drag proportions, fills inside shapes, and round-trips .wb JSON', () => {
    const rect: CanvasShape = {
      id: generateId(),
      kind: 'rectangle',
      start: { x: 20, y: 20 },
      end: { x: 120, y: 100 },
      color: { r: 0, g: 0.35, b: 1, a: 1 },
      presetIndex: 5,
      lineWidth: 3,
      isFilled: false,
      rotation: 0,
    };
    const arrow: CanvasShape = {
      id: generateId(),
      kind: 'arrow',
      start: { x: 0, y: 0 },
      end: { x: 100, y: 0 },
      color: { r: 0.95, g: 0, b: 0.1, a: 1 },
      presetIndex: 1,
      lineWidth: 2.5,
      isFilled: false,
      rotation: 0,
    };
    const label: TextLabel = {
      id: generateId(),
      text: 'Hello\nTissue Box',
      position: { x: 150, y: 50 },
      fontSize: 24,
      color: black,
      presetIndex: 0,
      isBold: true,
      rotation: Math.PI / 6,
    };

    expect(shapeContainsPoint(rect, { x: 20, y: 60 })).toBe(true);
    expect(shapeContainsPoint(rect, { x: 70, y: 60 })).toBe(false);
    expect(shapeContainsPoint(arrow, { x: 50, y: 1 })).toBe(true);
    expect(textLabelContainsPoint(label, textLabelCenter(label))).toBe(true);

    const sq = constrainShapeEnd({ x: 10, y: 10 }, { x: 90, y: 40 }, 'rectangle');
    expect(sq).toEqual({ x: 90, y: 90 });

    const contours = computeFillContours({ x: 70, y: 60 }, [], 2.0, [rect]);
    expect(contours).not.toBeNull();
    expect(contours!.length).toBeGreaterThanOrEqual(1);

    const encoded = encodeWBJson({
      strokes: [],
      placedImages: [],
      fills: [],
      scenes: [],
      shapes: [rect, arrow],
      textLabels: [label],
    });
    const decoded = decodeWBJson(encoded);
    expect(decoded.shapes?.length).toBe(2);
    expect(decoded.shapes?.[0].kind).toBe('rectangle');
    expect(decoded.shapes?.[1].kind).toBe('arrow');
    expect(decoded.textLabels?.length).toBe(1);
    expect(decoded.textLabels?.[0].text).toBe('Hello\nTissue Box');
    expect(decoded.textLabels?.[0].isBold).toBe(true);
  });

  it('supports DrawingStore shape/text creation, resize, rotate, recolor, undo, and vector PDF export', async () => {
    const store = new DrawingStore(false);

    // 1) Draw a Shift-constrained square with translucent fill
    store.selectTool('shape');
    store.setShapeKind('rectangle');
    store.setShapeSettings({ isFilled: true, lineWidth: 3 });
    store.selectShapePreset(5);
    store.beginShape({ x: 20, y: 20 });
    store.updateShape({ x: 120, y: 70 }, true);
    store.endShape();
    expect(store.getSnapshot().shapes.length).toBe(1);
    const rectId = store.getSnapshot().shapes[0].id;
    expect(store.getSnapshot().shapes[0].end).toEqual({ x: 120, y: 120 });

    // 2) Draw an arrow
    store.setShapeKind('arrow');
    store.beginShape({ x: 200, y: 20 });
    store.updateShape({ x: 320, y: 20 }, true);
    store.endShape();
    expect(store.getSnapshot().shapes.length).toBe(2);
    const arrowId = store.getSnapshot().shapes[1].id;

    // 3) Create and re-edit a multi-line TextLabel
    store.selectTool('text');
    store.setTextFontSize(30);
    store.toggleTextBold();
    store.selectTextPreset(1);
    store.beginTextEditing({ x: 40, y: 160 });
    store.setEditingTextDraft('System\nOverview');
    store.commitTextEditing();
    expect(store.getSnapshot().isEditingText).toBe(false);
    expect(store.getSnapshot().textLabels.length).toBe(1);
    const lblId = store.getSnapshot().textLabels[0].id;
    expect(store.getSnapshot().textLabels[0].isBold).toBe(true);

    store.beginTextEditing(store.getSnapshot().textLabels[0].position, lblId);
    store.setEditingTextDraft('Updated Label');
    store.commitTextEditing();
    expect(store.getSnapshot().textLabels[0].text).toBe('Updated Label');

    // 4) Select rectangle, resize via bottom-right handle, rotate 45°, reset rotation
    store.selectTool('select');
    expect(store.selectElement({ x: 20, y: 60 }, 1)).toBe(true);
    expect(store.getSnapshot().selectedShapeIds).toEqual([rectId]);
    const hit = store.hitTestShapeHandle({ x: 120, y: 120 }, 1);
    expect(hit).toEqual({ shapeId: rectId, handleIndex: 2 });
    store.beginMove({ x: 120, y: 120 }, 1);
    store.moveSelected({ width: 40, height: 20 });
    store.commitMove();
    expect(store.getSnapshot().shapes[0].end).toEqual({ x: 160, y: 140 });

    const geom = store.rotationHandleGeometry(1)!;
    expect(geom).not.toBeNull();
    store.beginRotate(geom.handleCenter, 1);
    store.updateRotate({ x: geom.pivot.x + 50, y: geom.pivot.y - 50 }, true);
    store.commitRotate();
    expect(store.getSnapshot().shapes[0].rotation).toBeCloseTo(Math.PI / 4, 4);
    expect(store.canResetSelectionRotation).toBe(true);
    store.resetSelectionRotation();
    expect(store.getSnapshot().shapes[0].rotation).toBeCloseTo(0, 5);

    // 5) Drag arrow endpoint handle
    expect(store.selectElement({ x: 260, y: 20 }, 1)).toBe(true);
    expect(store.getSnapshot().selectedShapeIds).toEqual([arrowId]);
    store.beginMove({ x: 320, y: 20 }, 1);
    store.moveSelected({ width: 30, height: 40 });
    store.commitMove();
    expect(store.getSnapshot().shapes[1].end).toEqual({ x: 350, y: 60 });

    // 6) Select text label, scale, recolor, duplicate, undo
    const lblCenter = textLabelCenter(store.getSnapshot().textLabels[0]);
    expect(store.selectElement(lblCenter, 1)).toBe(true);
    expect(store.getSnapshot().selectedTextIds).toEqual([lblId]);
    store.transformSelected(1.2, 0);
    expect(store.getSnapshot().textLabels[0].fontSize).toBeCloseTo(36, 1);
    store.recolorSelected(DEFAULT_LIGHT_PRESETS[4], 4);
    expect(store.getSnapshot().textLabels[0].presetIndex).toBe(4);
    store.duplicateSelected();
    expect(store.getSnapshot().textLabels.length).toBe(2);
    store.undo();
    expect(store.getSnapshot().textLabels.length).toBe(1);

    // 7) Export vector PDF containing shapes and selectable text
    const save = store.exportSaveData();
    const pdfBytes = await exportCanvasPDFBytes({
      strokes: save.strokes,
      placedImages: save.placedImages,
      fills: save.fills,
      shapes: save.shapes,
      textLabels: save.textLabels,
      penPresets: DEFAULT_LIGHT_PRESETS,
      sharpiePresets: DEFAULT_LIGHT_PRESETS,
      fillPresets: DEFAULT_LIGHT_PRESETS,
      shapePresets: DEFAULT_LIGHT_PRESETS,
      textPresets: DEFAULT_LIGHT_PRESETS,
      isDarkMode: false,
      isWarmPaper: false,
    });
    expect(pdfBytes).not.toBeNull();
    expect(new TextDecoder().decode(pdfBytes!.slice(0, 5))).toBe('%PDF-');
    expect(pdfBytes!.length).toBeGreaterThan(800);
  });

  it('parses Markdown blocks/inline spans, toggles formatting shortcuts, and exports Markdown vector PDF', async () => {
    const md = [
      '# Title',
      '## Subheading',
      'Plain **bold** *italic* <u>under</u> ~~strike~~ `code` snake_case',
      '- Bullet item',
      '1. Numbered item',
      '- [ ] Todo',
      '- [x] Done',
      '> Quoted note',
    ].join('\n');

    const lines = parseMarkdown(md);
    expect(lines.length).toBe(8);
    expect(lines[0].kind).toEqual({ type: 'heading', level: 1 });
    expect(lines[1].kind).toEqual({ type: 'heading', level: 2 });
    expect(lines[2].kind).toEqual({ type: 'paragraph' });
    expect(lines[2].spans.some((s) => s.text === 'bold' && s.isBold)).toBe(true);
    expect(lines[2].spans.some((s) => s.text === 'italic' && s.isItalic)).toBe(true);
    expect(lines[2].spans.some((s) => s.text === 'under' && s.isUnderline)).toBe(true);
    expect(lines[2].spans.some((s) => s.text === 'strike' && s.isStrikethrough)).toBe(true);
    expect(lines[2].spans.some((s) => s.text === 'code' && s.isCode)).toBe(true);
    expect(lines[2].spans.some((s) => s.text.includes('snake_case') && !s.isItalic)).toBe(true);
    expect(lines[3].kind).toEqual({ type: 'bullet', indentLevel: 0 });
    expect(lines[4].kind).toEqual({ type: 'numbered', marker: '1.', indentLevel: 0 });
    expect(lines[5].kind).toEqual({ type: 'checklist', checked: false, indentLevel: 0 });
    expect(lines[6].kind).toEqual({ type: 'checklist', checked: true, indentLevel: 0 });
    expect(lines[7].kind).toEqual({ type: 'blockquote' });

    // Formatting shortcut wrap/unwrap
    const wrapped = toggleMarkdownWrap('hello world', 6, 11, '**', '**');
    expect(wrapped).toEqual({ text: 'hello **world**', selectionStart: 8, selectionEnd: 13 });
    const unwrapped = toggleMarkdownWrap(wrapped.text, wrapped.selectionStart, wrapped.selectionEnd, '**', '**');
    expect(unwrapped).toEqual({ text: 'hello world', selectionStart: 6, selectionEnd: 11 });
    const collapsed = toggleMarkdownWrap('abc', 3, 3, '*', '*');
    expect(collapsed).toEqual({ text: 'abc**', selectionStart: 4, selectionEnd: 4 });
    const collapsedUnwrap = toggleMarkdownWrap(collapsed.text, 4, 4, '*', '*');
    expect(collapsedUnwrap).toEqual({ text: 'abc', selectionStart: 3, selectionEnd: 3 });

    // Heading measures taller than plain text
    const plain: TextLabel = {
      id: generateId(),
      text: 'Title',
      position: { x: 20, y: 20 },
      fontSize: 22,
      color: DEFAULT_LIGHT_PRESETS[0],
      presetIndex: 0,
      isBold: false,
      rotation: 0,
    };
    const heading: TextLabel = { ...plain, id: generateId(), text: '# Title' };
    expect(textLabelSize(heading).height).toBeGreaterThan(textLabelSize(plain).height);

    // Export vector PDF with Markdown text label
    const mdLabel: TextLabel = { ...plain, id: generateId(), text: md };
    const pdfBytes = await exportCanvasPDFBytes({
      strokes: [],
      placedImages: [],
      fills: [],
      shapes: [],
      textLabels: [mdLabel],
      penPresets: DEFAULT_LIGHT_PRESETS,
      sharpiePresets: DEFAULT_LIGHT_PRESETS,
      fillPresets: DEFAULT_LIGHT_PRESETS,
      shapePresets: DEFAULT_LIGHT_PRESETS,
      textPresets: DEFAULT_LIGHT_PRESETS,
      isDarkMode: false,
      isWarmPaper: false,
    });
    expect(pdfBytes).not.toBeNull();
    expect(new TextDecoder().decode(pdfBytes!.slice(0, 5))).toBe('%PDF-');
    expect(pdfBytes!.length).toBeGreaterThan(1000);
  });
});
