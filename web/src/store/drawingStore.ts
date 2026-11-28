import { useSyncExternalStore } from 'react';
import type {
  AppSettings,
  CanvasBackground,
  CanvasScene,
  CodableColor,
  EraserMode,
  EraserSettings,
  EraseTarget,
  FillOverlapMode,
  FillSettings,
  FillShape,
  PenSettings,
  PlacedImage,
  Point,
  Stroke,
  Tool,
  ToolbarDockEdge,
  ToolbarItemID,
} from '../types/model';
import {
  ALL_TOOLBAR_ITEMS,
  DEFAULT_PINNED_TOOLBAR_ITEMS,
  defaultAppSettings,
  defaultEraserSettings,
  defaultFillSettings,
  defaultPenSettings,
  generateId,
} from '../types/model';
import {
  distanceSquared,
  eraseFills,
  eraseStrokes,
  fillContainsPoint,
  recognizeShape,
  simplifyRDP,
  SpatialHashGrid,
} from '../engine/geometry';
import { computeFillContours } from '../engine/floodFill';
import { CanvasHistory, type CanvasSnapshot } from '../engine/history';

const SETTINGS_KEY = 'tissuebox.settings.v1';
const TOOLBAR_KEY = 'tissuebox.toolbar.v1';
const MIN_POINT_DIST_SQ = 1.25 * 1.25;

export interface DrawingState {
  strokes: Stroke[];
  fills: FillShape[];
  placedImages: PlacedImage[];
  scenes: CanvasScene[];
  activeSceneId: string | null;
  currentStroke: Stroke | null;
  currentTool: Tool;
  previousTool: Tool;
  penPresetIndex: number;
  sharpiePresetIndex: number;
  fillPresetIndex: number;
  penSettings: PenSettings;
  sharpieSettings: PenSettings;
  fillSettings: FillSettings;
  eraserSettings: EraserSettings;
  appSettings: AppSettings;
  pinnedToolbarItems: ToolbarItemID[];
  canUndo: boolean;
  canRedo: boolean;
  committedRevision: number;
  isToolbarVisible: boolean;
  lastErrorMessage: string | null;
  zoomDisplayScale: number;
}

class DrawingStore {
  private listeners = new Set<() => void>();
  private history = new CanvasHistory(100);
  readonly spatialGrid = new SpatialHashGrid(256);
  private state: DrawingState;

  constructor() {
    this.state = {
      strokes: [],
      fills: [],
      placedImages: [],
      scenes: [],
      activeSceneId: null,
      currentStroke: null,
      currentTool: 'pen',
      previousTool: 'pen',
      penPresetIndex: 0,
      sharpiePresetIndex: 0,
      fillPresetIndex: 5,
      penSettings: defaultPenSettings(),
      sharpieSettings: defaultPenSettings(),
      fillSettings: defaultFillSettings(),
      eraserSettings: defaultEraserSettings(),
      appSettings: defaultAppSettings(),
      pinnedToolbarItems: [...DEFAULT_PINNED_TOOLBAR_ITEMS],
      canUndo: false,
      canRedo: false,
      committedRevision: 0,
      isToolbarVisible: true,
      lastErrorMessage: null,
      zoomDisplayScale: 1,
    };
    this.loadPersistedSettings();
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): DrawingState => this.state;

  private emit(patch: Partial<DrawingState>, bumpCommitted = false): void {
    this.state = {
      ...this.state,
      ...patch,
      committedRevision: bumpCommitted
        ? this.state.committedRevision + 1
        : this.state.committedRevision,
    };
    for (const l of this.listeners) l();
  }

  private persistSettings(): void {
    if (typeof localStorage === 'undefined') return;
    try {
      const s = this.state;
      localStorage.setItem(
        SETTINGS_KEY,
        JSON.stringify({
          penSettings: s.penSettings,
          sharpieSettings: s.sharpieSettings,
          fillSettings: s.fillSettings,
          eraserSettings: s.eraserSettings,
          appSettings: s.appSettings,
          penPresetIndex: s.penPresetIndex,
          sharpiePresetIndex: s.sharpiePresetIndex,
          fillPresetIndex: s.fillPresetIndex,
          currentTool: s.currentTool,
        })
      );
      localStorage.setItem(TOOLBAR_KEY, JSON.stringify(s.pinnedToolbarItems));
    } catch {
      // ignore storage quota errors
    }
  }

  private loadPersistedSettings(): void {
    if (typeof localStorage === 'undefined') return;
    try {
      const raw = localStorage.getItem(SETTINGS_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed.penSettings) this.state.penSettings = { ...this.state.penSettings, ...parsed.penSettings };
        if (parsed.sharpieSettings) this.state.sharpieSettings = { ...this.state.sharpieSettings, ...parsed.sharpieSettings };
        if (parsed.fillSettings) this.state.fillSettings = { ...this.state.fillSettings, ...parsed.fillSettings };
        if (parsed.eraserSettings) this.state.eraserSettings = { ...this.state.eraserSettings, ...parsed.eraserSettings };
        if (parsed.appSettings) this.state.appSettings = { ...this.state.appSettings, ...parsed.appSettings };
        if (typeof parsed.penPresetIndex === 'number') this.state.penPresetIndex = parsed.penPresetIndex;
        if (typeof parsed.sharpiePresetIndex === 'number') this.state.sharpiePresetIndex = parsed.sharpiePresetIndex;
        if (typeof parsed.fillPresetIndex === 'number') this.state.fillPresetIndex = parsed.fillPresetIndex;
        if (parsed.currentTool) this.state.currentTool = parsed.currentTool;
      }
      const rawTb = localStorage.getItem(TOOLBAR_KEY);
      if (rawTb) {
        const arr = JSON.parse(rawTb) as ToolbarItemID[];
        const valid = new Set(ALL_TOOLBAR_ITEMS);
        const filtered = arr.filter((id) => valid.has(id));
        if (filtered.length > 0) this.state.pinnedToolbarItems = filtered;
      }
    } catch {
      // ignore corrupt settings
    }
  }

  private makeSnapshot(): CanvasSnapshot {
    return {
      strokes: this.state.strokes,
      placedImages: this.state.placedImages,
      fills: this.state.fills,
      selectedStrokeIds: [],
      selectedImageIds: [],
      selectedFillIds: [],
      selectionBoundary: [],
    };
  }

  private recordUndo(): void {
    this.history.record(this.makeSnapshot());
  }

  private syncUndoFlags(): { canUndo: boolean; canRedo: boolean } {
    return { canUndo: this.history.canUndo, canRedo: this.history.canRedo };
  }

  // MARK: - Active Presets & Colors

  get penPresets(): CodableColor[] {
    return this.state.appSettings.isDarkMode
      ? this.state.penSettings.darkPresets
      : this.state.penSettings.lightPresets;
  }

  get sharpiePresets(): CodableColor[] {
    return this.state.appSettings.isDarkMode
      ? this.state.sharpieSettings.darkPresets
      : this.state.sharpieSettings.lightPresets;
  }

  get fillPresets(): CodableColor[] {
    return this.state.appSettings.isDarkMode
      ? this.state.fillSettings.darkPresets
      : this.state.fillSettings.lightPresets;
  }

  get activePenColor(): CodableColor {
    return this.penPresets[this.state.penPresetIndex] ?? this.penPresets[0];
  }

  get activeSharpieColor(): CodableColor {
    return this.sharpiePresets[this.state.sharpiePresetIndex] ?? this.sharpiePresets[0];
  }

  get activeFillColor(): CodableColor {
    return this.fillPresets[this.state.fillPresetIndex] ?? this.fillPresets[0];
  }

  // MARK: - Tool & Settings

  selectTool(tool: Tool): void {
    const prev = this.state.currentTool !== tool ? this.state.currentTool : this.state.previousTool;
    this.emit({ currentTool: tool, previousTool: prev });
    this.persistSettings();
  }

  toggleEraserFromStylus(): void {
    if (this.state.currentTool === 'eraser') {
      const target = this.state.previousTool === 'eraser' ? 'pen' : this.state.previousTool;
      this.selectTool(target);
    } else {
      const prior = this.state.currentTool;
      const target: EraseTarget =
        prior === 'pen' ? 'pen' : prior === 'sharpie' ? 'sharpie' : prior === 'fill' ? 'fill' : 'all';
      this.selectTool('eraser');
      this.setEraserSettings({ eraseTarget: target });
    }
  }

  selectPenPreset(index: number): void {
    if (index < 0 || index >= this.penPresets.length) return;
    const color = this.penPresets[index];
    const penSettings = {
      ...this.state.penSettings,
      ...(this.state.appSettings.isDarkMode ? { darkColor: color } : { lightColor: color }),
    };
    this.emit({ penPresetIndex: index, penSettings });
    this.persistSettings();
  }

  updatePenPresetColor(index: number, color: CodableColor): void {
    const isDark = this.state.appSettings.isDarkMode;
    const nextPresets = (isDark ? this.state.penSettings.darkPresets : this.state.penSettings.lightPresets).map(
      (c, i) => (i === index ? color : c)
    );
    const penSettings: PenSettings = {
      ...this.state.penSettings,
      ...(isDark ? { darkPresets: nextPresets } : { lightPresets: nextPresets }),
      ...(this.state.penPresetIndex === index
        ? isDark
          ? { darkColor: color }
          : { lightColor: color }
        : {}),
    };
    this.emit({ penSettings }, true);
    this.persistSettings();
  }

  setPenThickness(thickness: number): void {
    this.emit({ penSettings: { ...this.state.penSettings, thickness } });
    this.persistSettings();
  }

  selectSharpiePreset(index: number): void {
    if (index < 0 || index >= this.sharpiePresets.length) return;
    const color = this.sharpiePresets[index];
    const sharpieSettings = {
      ...this.state.sharpieSettings,
      ...(this.state.appSettings.isDarkMode ? { darkColor: color } : { lightColor: color }),
    };
    this.emit({ sharpiePresetIndex: index, sharpieSettings });
    this.persistSettings();
  }

  updateSharpiePresetColor(index: number, color: CodableColor): void {
    const isDark = this.state.appSettings.isDarkMode;
    const nextPresets = (
      isDark ? this.state.sharpieSettings.darkPresets : this.state.sharpieSettings.lightPresets
    ).map((c, i) => (i === index ? color : c));
    const sharpieSettings: PenSettings = {
      ...this.state.sharpieSettings,
      ...(isDark ? { darkPresets: nextPresets } : { lightPresets: nextPresets }),
      ...(this.state.sharpiePresetIndex === index
        ? isDark
          ? { darkColor: color }
          : { lightColor: color }
        : {}),
    };
    this.emit({ sharpieSettings }, true);
    this.persistSettings();
  }

  setSharpieThickness(thickness: number): void {
    this.emit({ sharpieSettings: { ...this.state.sharpieSettings, thickness } });
    this.persistSettings();
  }

  selectFillPreset(index: number): void {
    if (index < 0 || index >= this.fillPresets.length) return;
    const color = this.fillPresets[index];
    const fillSettings = {
      ...this.state.fillSettings,
      ...(this.state.appSettings.isDarkMode ? { darkColor: color } : { lightColor: color }),
    };
    this.emit({ fillPresetIndex: index, fillSettings });
    this.persistSettings();
  }

  updateFillPresetColor(index: number, color: CodableColor): void {
    const isDark = this.state.appSettings.isDarkMode;
    const nextPresets = (
      isDark ? this.state.fillSettings.darkPresets : this.state.fillSettings.lightPresets
    ).map((c, i) => (i === index ? color : c));
    const fillSettings: FillSettings = {
      ...this.state.fillSettings,
      ...(isDark ? { darkPresets: nextPresets } : { lightPresets: nextPresets }),
      ...(this.state.fillPresetIndex === index
        ? isDark
          ? { darkColor: color }
          : { lightColor: color }
        : {}),
    };
    this.emit({ fillSettings }, true);
    this.persistSettings();
  }

  cycleFillOpacity(): void {
    const opts = this.state.fillSettings.opacityOptions;
    const cur = this.state.fillSettings.opacity;
    const idx = opts.findIndex((v) => Math.abs(v - cur) < 0.01);
    const next = opts[(idx + 1) % opts.length];
    this.emit({ fillSettings: { ...this.state.fillSettings, opacity: next } });
    this.persistSettings();
  }

  cycleFillGapTolerance(): void {
    const cur = this.state.fillSettings.gapTolerance;
    const next = cur < 1.0 ? 2.5 : cur < 4.0 ? 5.0 : 0;
    this.emit({ fillSettings: { ...this.state.fillSettings, gapTolerance: next } });
    this.persistSettings();
  }

  toggleFillOverlapMode(): void {
    const next: FillOverlapMode =
      this.state.fillSettings.overlapMode === 'replace' ? 'blend' : 'replace';
    this.emit({ fillSettings: { ...this.state.fillSettings, overlapMode: next } });
    this.persistSettings();
  }

  setEraserSettings(patch: Partial<EraserSettings>): void {
    this.emit({ eraserSettings: { ...this.state.eraserSettings, ...patch } });
    this.persistSettings();
  }

  cycleEraseTarget(): void {
    const order: EraseTarget[] = ['all', 'pen', 'sharpie', 'fill'];
    const idx = order.indexOf(this.state.eraserSettings.eraseTarget);
    this.setEraserSettings({ eraseTarget: order[(idx + 1) % order.length] });
  }

  setEraserMode(mode: EraserMode): void {
    this.setEraserSettings({ mode });
  }

  setAppSettings(patch: Partial<AppSettings>): void {
    this.emit({ appSettings: { ...this.state.appSettings, ...patch } }, true);
    this.persistSettings();
  }

  toggleDarkMode(): void {
    this.setAppSettings({ isDarkMode: !this.state.appSettings.isDarkMode });
  }

  toggleWarmPaper(): void {
    const next = !this.state.appSettings.isWarmPaper;
    this.setAppSettings({ isWarmPaper: next, isDarkMode: next ? false : this.state.appSettings.isDarkMode });
  }

  setCanvasBackground(bg: CanvasBackground): void {
    this.setAppSettings({ canvasBackground: bg });
  }

  cycleToolbarDockEdge(): void {
    const edges: ToolbarDockEdge[] = ['top', 'bottom', 'left', 'right'];
    const idx = edges.indexOf(this.state.appSettings.toolbarDockEdge);
    this.setAppSettings({ toolbarDockEdge: edges[(idx + 1) % edges.length] });
  }

  toggleToolbarVisible(): void {
    this.emit({ isToolbarVisible: !this.state.isToolbarVisible });
  }

  setZoomDisplayScale(scale: number): void {
    if (Math.abs(this.state.zoomDisplayScale - scale) > 0.005) {
      this.emit({ zoomDisplayScale: scale });
    }
  }

  setError(msg: string | null): void {
    this.emit({ lastErrorMessage: msg });
  }

  // MARK: - Drawing Strokes & Erasing

  beginStroke(point: Point, isEraser: boolean): void {
    const isSharpie = !isEraser && this.state.currentTool === 'sharpie';
    const color = isEraser
      ? { r: 1, g: 0, b: 0, a: 0.25 }
      : isSharpie
      ? this.activeSharpieColor
      : this.activePenColor;
    const lineWidth = isEraser
      ? this.state.eraserSettings.size
      : isSharpie
      ? this.state.sharpieSettings.thickness
      : this.state.penSettings.thickness;
    const presetIndex = isEraser
      ? -1
      : isSharpie
      ? this.state.sharpiePresetIndex
      : this.state.penPresetIndex;

    const stroke: Stroke = {
      id: generateId(),
      points: [point],
      color,
      lineWidth,
      isEraser,
      presetIndex,
      isCatmullRom: !isEraser,
      isSharpie,
    };
    this.emit({ currentStroke: stroke });
  }

  addStrokePoint(point: Point): void {
    const cur = this.state.currentStroke;
    if (!cur) return;
    const last = cur.points[cur.points.length - 1];
    if (last && distanceSquared(last, point) < MIN_POINT_DIST_SQ) return;
    cur.points.push(point);
    this.emit({ currentStroke: { ...cur } });
  }

  snapCurrentStrokeToShape(): boolean {
    const cur = this.state.currentStroke;
    if (!cur || cur.isEraser) return false;
    const snapped = recognizeShape(cur.points);
    if (!snapped) return false;
    this.emit({
      currentStroke: {
        ...cur,
        points: snapped,
        isCatmullRom: false,
      },
    });
    return true;
  }

  endStroke(viewScale = 1): void {
    const stroke = this.state.currentStroke;
    if (!stroke) return;

    if (stroke.isEraser) {
      const scaledEraser: Stroke = {
        ...stroke,
        lineWidth: this.state.eraserSettings.size / Math.max(viewScale, 0.01),
      };
      const nextStrokes = eraseStrokes(
        this.state.strokes,
        scaledEraser,
        this.state.eraserSettings.mode,
        this.state.eraserSettings.eraseTarget,
        generateId,
        this.spatialGrid
      );
      const nextFills = eraseFills(
        this.state.fills,
        scaledEraser,
        this.state.eraserSettings.eraseTarget
      );
      const changed =
        nextStrokes.length !== this.state.strokes.length ||
        nextFills.length !== this.state.fills.length ||
        nextStrokes.some((s, i) => s !== this.state.strokes[i]);
      if (changed) {
        this.recordUndo();
        this.spatialGrid.rebuild(nextStrokes);
        this.emit(
          {
            strokes: nextStrokes,
            fills: nextFills,
            currentStroke: null,
            ...this.syncUndoFlags(),
          },
          true
        );
      } else {
        this.emit({ currentStroke: null });
      }
      return;
    }

    if (stroke.points.length < 2) {
      this.emit({ currentStroke: null });
      return;
    }

    const finalStroke: Stroke = {
      ...stroke,
      points: stroke.isCatmullRom ? simplifyRDP(stroke.points, 0.35) : stroke.points,
    };
    this.recordUndo();
    const nextStrokes = [...this.state.strokes, finalStroke];
    this.spatialGrid.sync(nextStrokes);
    this.emit(
      {
        strokes: nextStrokes,
        currentStroke: null,
        ...this.syncUndoFlags(),
      },
      true
    );
  }

  // MARK: - Flood Fill

  floodFill(tapPoint: Point): boolean {
    const contours = computeFillContours(
      tapPoint,
      this.state.strokes,
      this.state.fillSettings.gapTolerance
    );
    if (!contours || contours.length === 0) return false;

    this.recordUndo();
    let nextFills = this.state.fills;
    if (this.state.fillSettings.overlapMode === 'replace') {
      nextFills = nextFills.filter((f) => !fillContainsPoint(f, tapPoint));
    }

    const newFill: FillShape = {
      id: generateId(),
      contours,
      color: this.activeFillColor,
      opacity: this.state.fillSettings.opacity,
      presetIndex: this.state.fillPresetIndex,
    };

    this.emit(
      {
        fills: [...nextFills, newFill],
        ...this.syncUndoFlags(),
      },
      true
    );
    return true;
  }

  // MARK: - Undo / Redo / Clear

  undo(): void {
    const prev = this.history.undo(this.makeSnapshot());
    if (!prev) return;
    this.spatialGrid.rebuild(prev.strokes);
    this.emit(
      {
        strokes: prev.strokes,
        placedImages: prev.placedImages,
        fills: prev.fills,
        currentStroke: null,
        ...this.syncUndoFlags(),
      },
      true
    );
  }

  redo(): void {
    const next = this.history.redo(this.makeSnapshot());
    if (!next) return;
    this.spatialGrid.rebuild(next.strokes);
    this.emit(
      {
        strokes: next.strokes,
        placedImages: next.placedImages,
        fills: next.fills,
        currentStroke: null,
        ...this.syncUndoFlags(),
      },
      true
    );
  }

  clearCanvas(): void {
    if (
      this.state.strokes.length === 0 &&
      this.state.fills.length === 0 &&
      this.state.placedImages.length === 0
    ) {
      return;
    }
    this.recordUndo();
    this.spatialGrid.invalidate();
    this.emit(
      {
        strokes: [],
        fills: [],
        placedImages: [],
        currentStroke: null,
        ...this.syncUndoFlags(),
      },
      true
    );
  }
}

export const drawingStore = new DrawingStore();

export function useDrawingState(): DrawingState {
  return useSyncExternalStore(drawingStore.subscribe, drawingStore.getSnapshot);
}
