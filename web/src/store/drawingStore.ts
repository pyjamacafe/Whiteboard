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
  Rect,
  SaveData,
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
  boundingBox,
  distanceSquared,
  eraseFills,
  eraseStrokes,
  fillBoundingBox,
  fillContainsPoint,
  imageCenter,
  imageContainsPoint,
  imageRotatedCorners,
  normalizeAngle,
  paddedBoundingPolygon,
  pointInPolygon,
  pointSegmentDistanceSquared,
  recognizeShape,
  resizedRect,
  simplifyRDP,
  snapRotationAngle,
  SpatialHashGrid,
} from '../engine/geometry';
import { computeFillContours } from '../engine/floodFill';
import { CanvasHistory, type CanvasSnapshot } from '../engine/history';
import { stripDataUrlPrefix } from '../engine/wbCodec';

const SETTINGS_KEY = 'tissuebox.settings.v1';
const TOOLBAR_KEY = 'tissuebox.toolbar.v1';
const MIN_POINT_DIST_SQ = 1.25 * 1.25;

export interface RotationHandleGeometry {
  pivot: Point;
  stemStart: Point;
  handleCenter: Point;
  displayAngleRadians: number;
}

interface ClipboardPayload {
  strokes: Stroke[];
  fills: FillShape[];
  placedImages: PlacedImage[];
  boundary: Point[];
}

export interface DrawingState {
  strokes: Stroke[];
  fills: FillShape[];
  placedImages: PlacedImage[];
  scenes: CanvasScene[];
  activeSceneId: string | null;
  pendingSceneNavigation: CanvasScene | null;
  needsRecenter: boolean;
  needsFitToContent: boolean;
  needsResetZoom: boolean;

  currentStroke: Stroke | null;
  currentTool: Tool;
  previousTool: Tool;

  selectionLasso: Point[];
  selectionBoundary: Point[];
  selectedStrokeIds: string[];
  selectedImageIds: string[];
  selectedFillIds: string[];
  isRotating: boolean;
  selectionRotationAngle: number;
  isRotationSnapped: boolean;
  showQuickMenu: boolean;
  quickMenuLocation: Point;

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
  currentViewportCenter: Point;
  currentViewportScale: number;
}

export class DrawingStore {
  private listeners = new Set<() => void>();
  private history = new CanvasHistory(100);
  readonly spatialGrid = new SpatialHashGrid(256);
  private state: DrawingState;
  private onAutoSaveHook: ((data: SaveData) => void) | null = null;
  private autoSaveTimer: number | null = null;

  // Non-reactive interaction tracking
  isMoving = false;
  isResizing = false;
  resizeCorner = 0;
  resizeImageId: string | null = null;
  resizeStartRect: Rect = { x: 0, y: 0, width: 0, height: 0 };
  lastMovePoint: Point = { x: 0, y: 0 };
  lastCanvasTapLocation: Point = { x: 0, y: 0 };
  pendingDeselectPoint: Point | null = null;
  private moveSnapshotTaken = false;

  private selectionRotationPivot: Point | null = null;
  private rotatePivot: Point = { x: 0, y: 0 };
  private rotateStartPointerAngle = 0;
  private rotateInitialSelectionAngle = 0;
  private rotateSnapshotStrokes = new Map<string, Point[]>();
  private rotateSnapshotFills = new Map<string, Point[][]>();
  private rotateSnapshotImages = new Map<
    string,
    { center: Point; size: { width: number; height: number }; rotation: number }
  >();
  private rotateSnapshotBoundary: Point[] = [];
  private rotateSnapshotTaken = false;
  private internalClipboard: ClipboardPayload | null = null;

  constructor(loadPersisted = true) {
    this.state = {
      strokes: [],
      fills: [],
      placedImages: [],
      scenes: [],
      activeSceneId: null,
      pendingSceneNavigation: null,
      needsRecenter: false,
      needsFitToContent: false,
      needsResetZoom: false,
      currentStroke: null,
      currentTool: 'pen',
      previousTool: 'pen',
      selectionLasso: [],
      selectionBoundary: [],
      selectedStrokeIds: [],
      selectedImageIds: [],
      selectedFillIds: [],
      isRotating: false,
      selectionRotationAngle: 0,
      isRotationSnapped: false,
      showQuickMenu: false,
      quickMenuLocation: { x: 0, y: 0 },
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
      currentViewportCenter: { x: 0, y: 0 },
      currentViewportScale: 1,
    };
    if (loadPersisted) {
      this.loadPersistedSettings();
    }
  }

  setAutoSaveHook(hook: ((data: SaveData) => void) | null): void {
    this.onAutoSaveHook = hook;
  }

  private scheduleAutoSave(): void {
    if (!this.onAutoSaveHook) return;
    if (typeof window === 'undefined') {
      this.onAutoSaveHook(this.exportSaveData());
      return;
    }
    if (this.autoSaveTimer !== null) {
      window.clearTimeout(this.autoSaveTimer);
    }
    this.autoSaveTimer = window.setTimeout(() => {
      this.autoSaveTimer = null;
      this.onAutoSaveHook?.(this.exportSaveData());
    }, 350);
  }

  flushAutoSave(): void {
    if (this.autoSaveTimer !== null && typeof window !== 'undefined') {
      window.clearTimeout(this.autoSaveTimer);
      this.autoSaveTimer = null;
    }
    this.onAutoSaveHook?.(this.exportSaveData());
  }

  exportSaveData(): SaveData {
    return {
      strokes: this.state.strokes,
      placedImages: this.state.placedImages,
      fills: this.state.fills,
      scenes: this.state.scenes,
    };
  }

  loadSaveData(data: SaveData): void {
    this.history.clear();
    this.spatialGrid.rebuild(data.strokes);
    this.resetSelectionRotationTracking();
    this.pendingDeselectPoint = null;
    this.emit(
      {
        strokes: data.strokes,
        fills: data.fills,
        placedImages: data.placedImages,
        scenes: data.scenes,
        activeSceneId: data.scenes[0]?.id ?? null,
        currentStroke: null,
        selectionLasso: [],
        selectionBoundary: [],
        selectedStrokeIds: [],
        selectedImageIds: [],
        selectedFillIds: [],
        showQuickMenu: false,
        canUndo: false,
        canRedo: false,
      },
      true
    );
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
      // ignore
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
      // ignore
    }
  }

  private makeSnapshot(): CanvasSnapshot {
    return {
      strokes: this.state.strokes,
      placedImages: this.state.placedImages,
      fills: this.state.fills,
      selectedStrokeIds: this.state.selectedStrokeIds,
      selectedImageIds: this.state.selectedImageIds,
      selectedFillIds: this.state.selectedFillIds,
      selectionBoundary: this.state.selectionBoundary,
    };
  }

  private recordUndo(): void {
    this.history.record(this.makeSnapshot());
  }

  private syncUndoFlags(): { canUndo: boolean; canRedo: boolean } {
    return { canUndo: this.history.canUndo, canRedo: this.history.canRedo };
  }

  // MARK: - Presets & Active Colors

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

  get hasSelection(): boolean {
    return (
      this.state.selectedStrokeIds.length > 0 ||
      this.state.selectedImageIds.length > 0 ||
      this.state.selectedFillIds.length > 0
    );
  }

  get hasAnySelectionOrLasso(): boolean {
    return (
      this.hasSelection ||
      this.state.selectionBoundary.length > 0 ||
      this.state.selectionLasso.length > 0
    );
  }

  get effectiveSelectionRotation(): number {
    if (
      this.state.selectedStrokeIds.length === 0 &&
      this.state.selectedFillIds.length === 0 &&
      this.state.selectedImageIds.length === 1
    ) {
      const img = this.state.placedImages.find((im) => im.id === this.state.selectedImageIds[0]);
      if (img) return normalizeAngle(img.rotation);
    }
    return normalizeAngle(this.state.selectionRotationAngle);
  }

  get canResetSelectionRotation(): boolean {
    if (Math.abs(this.effectiveSelectionRotation) > 0.001) return true;
    const selImgSet = new Set(this.state.selectedImageIds);
    for (const img of this.state.placedImages) {
      if (selImgSet.has(img.id) && Math.abs(normalizeAngle(img.rotation)) > 0.001) {
        return true;
      }
    }
    return false;
  }

  get activeRotationLabel(): string {
    let deg = Math.round((this.effectiveSelectionRotation * 180) / Math.PI);
    if (deg === -180) deg = 180;
    if (Object.is(deg, -0)) deg = 0;
    return `${deg}°`;
  }

  // MARK: - Configurable Toolbar

  get unpinnedToolbarItems(): ToolbarItemID[] {
    const pinned = new Set(this.state.pinnedToolbarItems);
    return ALL_TOOLBAR_ITEMS.filter((id) => !pinned.has(id));
  }

  pinToolbarItem(item: ToolbarItemID, before?: ToolbarItemID): void {
    if (item === before) return;
    const next = this.state.pinnedToolbarItems.filter((x) => x !== item);
    if (before) {
      const idx = next.indexOf(before);
      if (idx >= 0) next.splice(idx, 0, item);
      else next.push(item);
    } else {
      next.push(item);
    }
    this.emit({ pinnedToolbarItems: next });
    this.persistSettings();
  }

  unpinToolbarItem(item: ToolbarItemID): void {
    this.emit({ pinnedToolbarItems: this.state.pinnedToolbarItems.filter((x) => x !== item) });
    this.persistSettings();
  }

  resetToolbarLayout(): void {
    this.emit({
      pinnedToolbarItems: [...DEFAULT_PINNED_TOOLBAR_ITEMS],
      appSettings: { ...this.state.appSettings, toolbarDockEdge: 'top' },
    });
    this.persistSettings();
  }

  // MARK: - Tools & Settings

  selectTool(tool: Tool): void {
    const prev = this.state.currentTool !== tool ? this.state.currentTool : this.state.previousTool;
    if (tool !== 'select') {
      this.resetSelectionRotationTracking();
      this.pendingDeselectPoint = null;
      this.emit({
        currentTool: tool,
        previousTool: prev,
        selectedStrokeIds: [],
        selectedImageIds: [],
        selectedFillIds: [],
        selectionBoundary: [],
        selectionLasso: [],
        showQuickMenu: false,
      });
    } else {
      this.emit({ currentTool: tool, previousTool: prev, showQuickMenu: false });
    }
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
    this.emit({
      penPresetIndex: index,
      penSettings: {
        ...this.state.penSettings,
        ...(this.state.appSettings.isDarkMode ? { darkColor: color } : { lightColor: color }),
      },
    });
    this.persistSettings();
  }

  updatePenPresetColor(index: number, color: CodableColor): void {
    const isDark = this.state.appSettings.isDarkMode;
    const nextPresets = (isDark ? this.state.penSettings.darkPresets : this.state.penSettings.lightPresets).map(
      (c, i) => (i === index ? color : c)
    );
    this.emit(
      {
        penSettings: {
          ...this.state.penSettings,
          ...(isDark ? { darkPresets: nextPresets } : { lightPresets: nextPresets }),
          ...(this.state.penPresetIndex === index
            ? isDark
              ? { darkColor: color }
              : { lightColor: color }
            : {}),
        },
      },
      true
    );
    this.persistSettings();
  }

  setPenThickness(thickness: number): void {
    this.emit({ penSettings: { ...this.state.penSettings, thickness } });
    this.persistSettings();
  }

  selectSharpiePreset(index: number): void {
    if (index < 0 || index >= this.sharpiePresets.length) return;
    const color = this.sharpiePresets[index];
    this.emit({
      sharpiePresetIndex: index,
      sharpieSettings: {
        ...this.state.sharpieSettings,
        ...(this.state.appSettings.isDarkMode ? { darkColor: color } : { lightColor: color }),
      },
    });
    this.persistSettings();
  }

  updateSharpiePresetColor(index: number, color: CodableColor): void {
    const isDark = this.state.appSettings.isDarkMode;
    const nextPresets = (
      isDark ? this.state.sharpieSettings.darkPresets : this.state.sharpieSettings.lightPresets
    ).map((c, i) => (i === index ? color : c));
    this.emit(
      {
        sharpieSettings: {
          ...this.state.sharpieSettings,
          ...(isDark ? { darkPresets: nextPresets } : { lightPresets: nextPresets }),
          ...(this.state.sharpiePresetIndex === index
            ? isDark
              ? { darkColor: color }
              : { lightColor: color }
            : {}),
        },
      },
      true
    );
    this.persistSettings();
  }

  setSharpieThickness(thickness: number): void {
    this.emit({ sharpieSettings: { ...this.state.sharpieSettings, thickness } });
    this.persistSettings();
  }

  selectFillPreset(index: number): void {
    if (index < 0 || index >= this.fillPresets.length) return;
    const color = this.fillPresets[index];
    this.emit({
      fillPresetIndex: index,
      fillSettings: {
        ...this.state.fillSettings,
        ...(this.state.appSettings.isDarkMode ? { darkColor: color } : { lightColor: color }),
      },
    });
    this.persistSettings();
  }

  updateFillPresetColor(index: number, color: CodableColor): void {
    const isDark = this.state.appSettings.isDarkMode;
    const nextPresets = (
      isDark ? this.state.fillSettings.darkPresets : this.state.fillSettings.lightPresets
    ).map((c, i) => (i === index ? color : c));
    this.emit(
      {
        fillSettings: {
          ...this.state.fillSettings,
          ...(isDark ? { darkPresets: nextPresets } : { lightPresets: nextPresets }),
          ...(this.state.fillPresetIndex === index
            ? isDark
              ? { darkColor: color }
              : { lightColor: color }
            : {}),
        },
      },
      true
    );
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
    this.setAppSettings({
      isWarmPaper: next,
      isDarkMode: next ? false : this.state.appSettings.isDarkMode,
    });
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

  reportViewport(center: Point, scale: number): void {
    this.state.currentViewportCenter = center;
    this.state.currentViewportScale = scale;
    if (Math.abs(this.state.zoomDisplayScale - scale) > 0.005) {
      this.emit({ zoomDisplayScale: scale });
    }
  }

  requestRecenter(): void {
    this.emit({ needsRecenter: true });
  }
  consumeRecenter(): void {
    if (this.state.needsRecenter) this.emit({ needsRecenter: false });
  }
  requestFitToContent(): void {
    this.emit({ needsFitToContent: true });
  }
  consumeFitToContent(): void {
    if (this.state.needsFitToContent) this.emit({ needsFitToContent: false });
  }
  requestResetZoom(): void {
    this.emit({ needsResetZoom: true });
  }
  consumeResetZoom(): void {
    if (this.state.needsResetZoom) this.emit({ needsResetZoom: false });
  }
  consumePendingSceneNavigation(): void {
    if (this.state.pendingSceneNavigation) this.emit({ pendingSceneNavigation: null });
  }

  setQuickMenu(show: boolean, location?: Point): void {
    this.emit({
      showQuickMenu: show,
      ...(location ? { quickMenuLocation: location } : {}),
    });
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

    this.emit({
      currentStroke: {
        id: generateId(),
        points: [point],
        color,
        lineWidth,
        isEraser,
        presetIndex,
        isCatmullRom: !isEraser,
        isSharpie,
      },
      showQuickMenu: false,
    });
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
      currentStroke: { ...cur, points: snapped, isCatmullRom: false },
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
        this.scheduleAutoSave();
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
    this.scheduleAutoSave();
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

    this.emit({ fills: [...nextFills, newFill], ...this.syncUndoFlags() }, true);
    this.scheduleAutoSave();
    return true;
  }

  // MARK: - Lasso & Tap-to-Select

  beginLasso(point: Point): void {
    this.emit({ selectionLasso: [point], showQuickMenu: false });
  }

  addLassoPoint(point: Point): void {
    const cur = this.state.selectionLasso;
    if (cur.length > 0 && distanceSquared(cur[cur.length - 1], point) < 25) return;
    this.emit({ selectionLasso: [...cur, point] });
  }

  endLasso(scale = 1): void {
    const lasso = this.state.selectionLasso;
    if (lasso.length < 3) {
      const tapPoint = lasso[0];
      this.emit({ selectionLasso: [] });
      if (tapPoint) {
        this.selectElement(tapPoint, scale);
      }
      return;
    }

    // Lasso bounding box for spatial query
    let minX = lasso[0].x;
    let maxX = minX;
    let minY = lasso[0].y;
    let maxY = minY;
    for (const p of lasso) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    const lassoBox: Rect = { x: minX, y: minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) };

    const hitStrokes: string[] = [];
    this.spatialGrid.sync(this.state.strokes);
    for (const idx of this.spatialGrid.queryIndices(lassoBox)) {
      const s = this.state.strokes[idx];
      if (s.isEraser) continue;
      if (s.points.some((p) => pointInPolygon(p, lasso))) {
        hitStrokes.push(s.id);
      }
    }

    const hitFills: string[] = [];
    for (const f of this.state.fills) {
      const fb = fillBoundingBox(f);
      if (!fb) continue;
      const center = { x: fb.x + fb.width / 2, y: fb.y + fb.height / 2 };
      if (
        pointInPolygon(center, lasso) ||
        (f.contours[0] && f.contours[0].some((p) => pointInPolygon(p, lasso)))
      ) {
        hitFills.push(f.id);
      }
    }

    const hitImages: string[] = [];
    for (const img of this.state.placedImages) {
      if (
        pointInPolygon(imageCenter(img), lasso) ||
        imageRotatedCorners(img).some((c) => pointInPolygon(c, lasso))
      ) {
        hitImages.push(img.id);
      }
    }

    if (hitStrokes.length === 0 && hitFills.length === 0 && hitImages.length === 0) {
      this.clearSelection();
      this.emit({ selectionLasso: [] });
      return;
    }

    this.recordUndo();
    this.resetSelectionRotationTracking();
    this.emit({
      selectedStrokeIds: hitStrokes,
      selectedFillIds: hitFills,
      selectedImageIds: hitImages,
      selectionBoundary: lasso,
      selectionLasso: [],
      ...this.syncUndoFlags(),
    });
  }

  private hitTestStroke(point: Point, scale: number): Stroke | null {
    const baseRadius = Math.max(10, 12 / Math.max(scale, 0.1));
    const qR = baseRadius + 12;
    const queryRect: Rect = { x: point.x - qR, y: point.y - qR, width: qR * 2, height: qR * 2 };
    this.spatialGrid.sync(this.state.strokes);
    const candidates = this.spatialGrid.queryIndices(queryRect).sort((a, b) => b - a);
    for (const idx of candidates) {
      const s = this.state.strokes[idx];
      if (s.isEraser || s.points.length === 0) continue;
      const halfW = (s.isSharpie ? s.lineWidth + 3 : s.lineWidth) / 2;
      const hitR = baseRadius + halfW;
      const hitRSq = hitR * hitR;
      if (s.points.length === 1) {
        if (distanceSquared(point, s.points[0]) <= hitRSq) return s;
      } else {
        for (let i = 0; i < s.points.length - 1; i++) {
          if (pointSegmentDistanceSquared(point, s.points[i], s.points[i + 1]) <= hitRSq) {
            return s;
          }
        }
      }
    }
    return null;
  }

  private hitTestFill(point: Point): FillShape | null {
    for (let i = this.state.fills.length - 1; i >= 0; i--) {
      const f = this.state.fills[i];
      if (fillContainsPoint(f, point)) return f;
    }
    return null;
  }

  hitTestImage(point: Point): string | null {
    for (let i = this.state.placedImages.length - 1; i >= 0; i--) {
      const img = this.state.placedImages[i];
      if (imageContainsPoint(img, point)) return img.id;
    }
    return null;
  }

  hasElement(point: Point, scale = 1): boolean {
    return (
      this.hitTestStroke(point, scale) !== null ||
      this.hitTestFill(point) !== null ||
      this.hitTestImage(point) !== null
    );
  }

  selectElement(point: Point, scale = 1): boolean {
    const stroke = this.hitTestStroke(point, scale);
    if (stroke) {
      this.recordUndo();
      this.resetSelectionRotationTracking();
      const box = boundingBox([stroke], [], [], 8);
      this.emit({
        selectedStrokeIds: [stroke.id],
        selectedFillIds: [],
        selectedImageIds: [],
        selectionBoundary: box ? paddedBoundingPolygon(box) : [],
        selectionLasso: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      });
      return true;
    }

    const fill = this.hitTestFill(point);
    if (fill) {
      this.recordUndo();
      this.resetSelectionRotationTracking();
      const fb = fillBoundingBox(fill);
      const box = fb
        ? { x: fb.x - 8, y: fb.y - 8, width: fb.width + 16, height: fb.height + 16 }
        : null;
      this.emit({
        selectedStrokeIds: [],
        selectedFillIds: [fill.id],
        selectedImageIds: [],
        selectionBoundary: box ? paddedBoundingPolygon(box) : [],
        selectionLasso: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      });
      return true;
    }

    const imgId = this.hitTestImage(point);
    if (imgId) {
      this.recordUndo();
      this.resetSelectionRotationTracking();
      this.emit({
        selectedStrokeIds: [],
        selectedFillIds: [],
        selectedImageIds: [imgId],
        selectionBoundary: [],
        selectionLasso: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      });
      return true;
    }

    return false;
  }

  resetSelectionRotationTracking(): void {
    this.selectionRotationPivot = null;
    this.rotateSnapshotStrokes.clear();
    this.rotateSnapshotFills.clear();
    this.rotateSnapshotImages.clear();
    this.rotateSnapshotBoundary = [];
    this.rotateSnapshotTaken = false;
    if (
      this.state.isRotating ||
      this.state.selectionRotationAngle !== 0 ||
      this.state.isRotationSnapped
    ) {
      this.emit({
        isRotating: false,
        selectionRotationAngle: 0,
        isRotationSnapped: false,
      });
    }
  }

  clearSelection(): void {
    this.resetSelectionRotationTracking();
    this.emit({
      selectedStrokeIds: [],
      selectedImageIds: [],
      selectedFillIds: [],
      selectionBoundary: [],
      showQuickMenu: false,
    });
  }

  clearLassoSelection(): void {
    if (this.state.isRotating) this.commitRotate();
    if (this.isMoving || this.isResizing) this.commitMove();
    this.pendingDeselectPoint = null;
    this.resetSelectionRotationTracking();
    this.emit({
      selectedStrokeIds: [],
      selectedImageIds: [],
      selectedFillIds: [],
      selectionBoundary: [],
      selectionLasso: [],
      showQuickMenu: false,
    });
  }

  isPointInSelectionBoundary(point: Point): boolean {
    return pointInPolygon(point, this.state.selectionBoundary);
  }

  isPointOnSelectedItem(point: Point): boolean {
    const selS = new Set(this.state.selectedStrokeIds);
    const threshSq = 15 * 15;
    for (const s of this.state.strokes) {
      if (!selS.has(s.id) || s.points.length < 2) continue;
      for (let i = 0; i < s.points.length - 1; i++) {
        if (pointSegmentDistanceSquared(point, s.points[i], s.points[i + 1]) < threshSq) {
          return true;
        }
      }
    }
    const selI = new Set(this.state.selectedImageIds);
    for (const img of this.state.placedImages) {
      if (selI.has(img.id) && imageContainsPoint(img, point)) return true;
    }
    const selF = new Set(this.state.selectedFillIds);
    for (const f of this.state.fills) {
      if (selF.has(f.id) && fillContainsPoint(f, point)) return true;
    }
    return false;
  }

  // MARK: - Rotation Handle & Resize Handles

  rotationHandleGeometry(scale: number): RotationHandleGeometry | null {
    if (!this.hasSelection) return null;
    const stemLength = 28 / Math.max(scale, 0.1);

    if (
      this.state.selectedStrokeIds.length === 0 &&
      this.state.selectedFillIds.length === 0 &&
      this.state.selectedImageIds.length === 1
    ) {
      const img = this.state.placedImages.find((im) => im.id === this.state.selectedImageIds[0]);
      if (!img) return null;
      const pivot = imageCenter(img);
      const angle = normalizeAngle(img.rotation);
      const up = { x: Math.sin(angle), y: -Math.cos(angle) };
      const halfH = img.size.height / 2;
      return {
        pivot,
        stemStart: { x: pivot.x + up.x * halfH, y: pivot.y + up.y * halfH },
        handleCenter: {
          x: pivot.x + up.x * (halfH + stemLength),
          y: pivot.y + up.y * (halfH + stemLength),
        },
        displayAngleRadians: angle,
      };
    }

    const selS = new Set(this.state.selectedStrokeIds);
    const selI = new Set(this.state.selectedImageIds);
    const selF = new Set(this.state.selectedFillIds);
    const selStrokes = this.state.strokes.filter((s) => selS.has(s.id));
    const selImages = this.state.placedImages.filter((im) => selI.has(im.id));
    const selFills = this.state.fills.filter((f) => selF.has(f.id));
    const box = boundingBox(selStrokes, selImages, selFills, 0);
    if (!box) return null;

    const pivot = this.state.isRotating
      ? this.rotatePivot
      : this.selectionRotationPivot ?? { x: box.x + box.width / 2, y: box.y + box.height / 2 };

    const angle = normalizeAngle(this.state.selectionRotationAngle);
    const up = { x: Math.sin(angle), y: -Math.cos(angle) };

    let maxExtent = 0;
    const consider = (p: Point) => {
      const proj = (p.x - pivot.x) * up.x + (p.y - pivot.y) * up.y;
      if (proj > maxExtent) maxExtent = proj;
    };
    for (const s of selStrokes) for (const p of s.points) consider(p);
    for (const f of selFills) for (const loop of f.contours) for (const p of loop) consider(p);
    for (const img of selImages) for (const c of imageRotatedCorners(img)) consider(c);
    for (const p of this.state.selectionBoundary) consider(p);

    return {
      pivot,
      stemStart: { x: pivot.x + up.x * maxExtent, y: pivot.y + up.y * maxExtent },
      handleCenter: {
        x: pivot.x + up.x * (maxExtent + stemLength),
        y: pivot.y + up.y * (maxExtent + stemLength),
      },
      displayAngleRadians: angle,
    };
  }

  hitTestRotateHandle(point: Point, scale = 1): boolean {
    const geom = this.rotationHandleGeometry(scale);
    if (!geom) return false;
    const r = 16 / Math.max(scale, 0.1);
    return distanceSquared(point, geom.handleCenter) <= r * r;
  }

  hitTestResizeHandle(point: Point, scale = 1): { imgId: string; corner: number } | null {
    const r = Math.max(10, 12 / Math.max(scale, 0.1));
    const rSq = r * r;
    const selI = new Set(this.state.selectedImageIds);
    for (const img of this.state.placedImages) {
      if (!selI.has(img.id)) continue;
      const corners = imageRotatedCorners(img);
      for (let c = 0; c < corners.length; c++) {
        if (distanceSquared(point, corners[c]) <= rSq) {
          return { imgId: img.id, corner: c };
        }
      }
    }
    return null;
  }

  beginRotate(point: Point, scale = 1): void {
    const geom = this.rotationHandleGeometry(scale);
    if (!geom) return;
    this.isMoving = false;
    this.isResizing = false;
    this.rotatePivot = geom.pivot;
    this.selectionRotationPivot = geom.pivot;
    this.rotateStartPointerAngle = Math.atan2(point.y - geom.pivot.y, point.x - geom.pivot.x);
    this.rotateInitialSelectionAngle = this.effectiveSelectionRotation;
    this.rotateSnapshotTaken = false;

    const selS = new Set(this.state.selectedStrokeIds);
    const selF = new Set(this.state.selectedFillIds);
    const selI = new Set(this.state.selectedImageIds);

    this.rotateSnapshotStrokes.clear();
    for (const s of this.state.strokes) {
      if (selS.has(s.id)) this.rotateSnapshotStrokes.set(s.id, s.points.map((p) => ({ ...p })));
    }
    this.rotateSnapshotFills.clear();
    for (const f of this.state.fills) {
      if (selF.has(f.id)) {
        this.rotateSnapshotFills.set(
          f.id,
          f.contours.map((loop) => loop.map((p) => ({ ...p })))
        );
      }
    }
    this.rotateSnapshotImages.clear();
    for (const img of this.state.placedImages) {
      if (selI.has(img.id)) {
        this.rotateSnapshotImages.set(img.id, {
          center: imageCenter(img),
          size: { ...img.size },
          rotation: img.rotation,
        });
      }
    }
    this.rotateSnapshotBoundary = this.state.selectionBoundary.map((p) => ({ ...p }));
    this.emit({ isRotating: true, isRotationSnapped: false, showQuickMenu: false });
  }

  updateRotate(point: Point, snapTo15Degrees = false): void {
    if (!this.state.isRotating) return;
    const curPointer = Math.atan2(point.y - this.rotatePivot.y, point.x - this.rotatePivot.x);
    const rawDelta = curPointer - this.rotateStartPointerAngle;
    const { angle: snappedTotal, snapped } = snapRotationAngle(
      this.rotateInitialSelectionAngle + rawDelta,
      snapTo15Degrees
    );
    const appliedDelta = snappedTotal - this.rotateInitialSelectionAngle;

    if (Math.abs(appliedDelta) > 1e-6 && !this.rotateSnapshotTaken) {
      this.recordUndo();
      this.rotateSnapshotTaken = true;
    }

    const pivot = this.rotatePivot;
    const cosA = Math.cos(appliedDelta);
    const sinA = Math.sin(appliedDelta);
    const rot = (p: Point): Point => {
      const dx = p.x - pivot.x;
      const dy = p.y - pivot.y;
      return { x: pivot.x + dx * cosA - dy * sinA, y: pivot.y + dx * sinA + dy * cosA };
    };

    const nextStrokes =
      this.rotateSnapshotStrokes.size > 0
        ? this.state.strokes.map((s) => {
            const orig = this.rotateSnapshotStrokes.get(s.id);
            return orig ? { ...s, points: orig.map(rot) } : s;
          })
        : this.state.strokes;

    const nextFills =
      this.rotateSnapshotFills.size > 0
        ? this.state.fills.map((f) => {
            const orig = this.rotateSnapshotFills.get(f.id);
            return orig ? { ...f, contours: orig.map((loop) => loop.map(rot)) } : f;
          })
        : this.state.fills;

    const nextImages =
      this.rotateSnapshotImages.size > 0
        ? this.state.placedImages.map((img) => {
            const orig = this.rotateSnapshotImages.get(img.id);
            if (!orig) return img;
            const newCenter = rot(orig.center);
            return {
              ...img,
              position: {
                x: newCenter.x - orig.size.width / 2,
                y: newCenter.y - orig.size.height / 2,
              },
              rotation: normalizeAngle(orig.rotation + appliedDelta),
            };
          })
        : this.state.placedImages;

    const nextBoundary =
      this.rotateSnapshotBoundary.length > 0
        ? this.rotateSnapshotBoundary.map(rot)
        : this.state.selectionBoundary;

    this.emit(
      {
        strokes: nextStrokes,
        fills: nextFills,
        placedImages: nextImages,
        selectionBoundary: nextBoundary,
        selectionRotationAngle: snappedTotal,
        isRotationSnapped: snapped,
      },
      true
    );
  }

  commitRotate(): void {
    const didMutate = this.rotateSnapshotTaken;
    this.rotateSnapshotStrokes.clear();
    this.rotateSnapshotFills.clear();
    this.rotateSnapshotImages.clear();
    this.rotateSnapshotBoundary = [];
    this.rotateSnapshotTaken = false;
    if (didMutate) {
      this.spatialGrid.rebuild(this.state.strokes);
      this.emit({ isRotating: false, isRotationSnapped: false, ...this.syncUndoFlags() });
      this.scheduleAutoSave();
    } else {
      this.emit({ isRotating: false, isRotationSnapped: false });
    }
  }

  resetSelectionRotation(): void {
    if (!this.canResetSelectionRotation) return;
    this.recordUndo();

    const selI = new Set(this.state.selectedImageIds);
    if (this.state.selectedStrokeIds.length === 0 && this.state.selectedFillIds.length === 0) {
      const nextImages = this.state.placedImages.map((img) =>
        selI.has(img.id) ? { ...img, rotation: 0 } : img
      );
      this.resetSelectionRotationTracking();
      this.emit({ placedImages: nextImages, ...this.syncUndoFlags() }, true);
      this.scheduleAutoSave();
      return;
    }

    const sessionAngle = normalizeAngle(this.state.selectionRotationAngle);
    let nextStrokes = this.state.strokes;
    let nextFills = this.state.fills;
    let nextImages = this.state.placedImages;
    let nextBoundary = this.state.selectionBoundary;

    if (Math.abs(sessionAngle) > 0.001) {
      const delta = -sessionAngle;
      const selS = new Set(this.state.selectedStrokeIds);
      const selF = new Set(this.state.selectedFillIds);
      const box = boundingBox(
        this.state.strokes.filter((s) => selS.has(s.id)),
        this.state.placedImages.filter((im) => selI.has(im.id)),
        this.state.fills.filter((f) => selF.has(f.id)),
        0
      );
      const pivot =
        this.selectionRotationPivot ??
        (box ? { x: box.x + box.width / 2, y: box.y + box.height / 2 } : { x: 0, y: 0 });
      const cosA = Math.cos(delta);
      const sinA = Math.sin(delta);
      const rot = (p: Point): Point => {
        const dx = p.x - pivot.x;
        const dy = p.y - pivot.y;
        return { x: pivot.x + dx * cosA - dy * sinA, y: pivot.y + dx * sinA + dy * cosA };
      };

      if (selS.size > 0) {
        nextStrokes = nextStrokes.map((s) => (selS.has(s.id) ? { ...s, points: s.points.map(rot) } : s));
      }
      if (selF.size > 0) {
        nextFills = nextFills.map((f) =>
          selF.has(f.id) ? { ...f, contours: f.contours.map((loop) => loop.map(rot)) } : f
        );
      }
      if (selI.size > 0) {
        nextImages = nextImages.map((img) => {
          if (!selI.has(img.id)) return img;
          const nc = rot(imageCenter(img));
          return {
            ...img,
            position: { x: nc.x - img.size.width / 2, y: nc.y - img.size.height / 2 },
            rotation: normalizeAngle(img.rotation + delta),
          };
        });
      }
      if (nextBoundary.length > 0) nextBoundary = nextBoundary.map(rot);
    } else if (selI.size > 0) {
      nextImages = nextImages.map((img) => (selI.has(img.id) ? { ...img, rotation: 0 } : img));
    }

    this.resetSelectionRotationTracking();
    this.spatialGrid.rebuild(nextStrokes);
    this.emit(
      {
        strokes: nextStrokes,
        fills: nextFills,
        placedImages: nextImages,
        selectionBoundary: nextBoundary,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
  }

  // MARK: - Move & Resize

  beginMove(point: Point, scale = 1): void {
    const hit = this.hitTestResizeHandle(point, scale);
    if (hit) {
      this.isResizing = true;
      this.isMoving = false;
      this.resizeCorner = hit.corner;
      this.resizeImageId = hit.imgId;
      this.lastMovePoint = point;
      this.moveSnapshotTaken = false;
      const img = this.state.placedImages.find((im) => im.id === hit.imgId);
      if (img) {
        this.resizeStartRect = {
          x: img.position.x,
          y: img.position.y,
          width: img.size.width,
          height: img.size.height,
        };
      }
      this.emit({ showQuickMenu: false });
      return;
    }

    this.isMoving = true;
    this.isResizing = false;
    this.lastMovePoint = point;
    this.moveSnapshotTaken = false;
    this.emit({ showQuickMenu: false });
  }

  moveSelected(offset: { width: number; height: number }): void {
    if (offset.width === 0 && offset.height === 0) return;

    if (this.isResizing) {
      if (!this.resizeImageId) return;
      const existing = this.state.placedImages.find((im) => im.id === this.resizeImageId);
      if (!existing) return;

      const rot = existing.rotation || 0;
      let localOffset = offset;
      if (rot !== 0) {
        const cosA = Math.cos(-rot);
        const sinA = Math.sin(-rot);
        localOffset = {
          width: offset.width * cosA - offset.height * sinA,
          height: offset.width * sinA + offset.height * cosA,
        };
      }
      const newLocal = resizedRect(this.resizeStartRect, this.resizeCorner, localOffset);
      if (!newLocal) return;

      let finalRect = newLocal;
      if (rot !== 0) {
        const oldCx = this.resizeStartRect.x + this.resizeStartRect.width / 2;
        const oldCy = this.resizeStartRect.y + this.resizeStartRect.height / 2;
        const ldx = newLocal.x + newLocal.width / 2 - oldCx;
        const ldy = newLocal.y + newLocal.height / 2 - oldCy;
        const cosA = Math.cos(rot);
        const sinA = Math.sin(rot);
        const newCx = oldCx + ldx * cosA - ldy * sinA;
        const newCy = oldCy + ldx * sinA + ldy * cosA;
        finalRect = {
          x: newCx - newLocal.width / 2,
          y: newCy - newLocal.height / 2,
          width: newLocal.width,
          height: newLocal.height,
        };
      }

      if (!this.moveSnapshotTaken) {
        this.recordUndo();
        this.moveSnapshotTaken = true;
      }
      const nextImages = this.state.placedImages.map((img) =>
        img.id === this.resizeImageId
          ? {
              ...img,
              position: { x: finalRect.x, y: finalRect.y },
              size: { width: finalRect.width, height: finalRect.height },
            }
          : img
      );
      this.resizeStartRect = finalRect;
      this.emit({ placedImages: nextImages }, true);
      return;
    }

    if (!this.isMoving) return;
    if (!this.moveSnapshotTaken) {
      this.recordUndo();
      this.moveSnapshotTaken = true;
    }
    const selS = new Set(this.state.selectedStrokeIds);
    const selI = new Set(this.state.selectedImageIds);
    const selF = new Set(this.state.selectedFillIds);

    const nextStrokes =
      selS.size > 0
        ? this.state.strokes.map((s) =>
            selS.has(s.id)
              ? { ...s, points: s.points.map((p) => ({ x: p.x + offset.width, y: p.y + offset.height })) }
              : s
          )
        : this.state.strokes;

    const nextImages =
      selI.size > 0
        ? this.state.placedImages.map((img) =>
            selI.has(img.id)
              ? {
                  ...img,
                  position: { x: img.position.x + offset.width, y: img.position.y + offset.height },
                }
              : img
          )
        : this.state.placedImages;

    const nextFills =
      selF.size > 0
        ? this.state.fills.map((f) =>
            selF.has(f.id)
              ? {
                  ...f,
                  contours: f.contours.map((loop) =>
                    loop.map((p) => ({ x: p.x + offset.width, y: p.y + offset.height }))
                  ),
                }
              : f
          )
        : this.state.fills;

    const nextBoundary = this.state.selectionBoundary.map((p) => ({
      x: p.x + offset.width,
      y: p.y + offset.height,
    }));

    if (this.selectionRotationPivot) {
      this.selectionRotationPivot = {
        x: this.selectionRotationPivot.x + offset.width,
        y: this.selectionRotationPivot.y + offset.height,
      };
    }

    this.emit(
      {
        strokes: nextStrokes,
        placedImages: nextImages,
        fills: nextFills,
        selectionBoundary: nextBoundary,
      },
      true
    );
  }

  commitMove(): void {
    const didMutate = this.moveSnapshotTaken;
    this.isMoving = false;
    this.isResizing = false;
    this.resizeImageId = null;
    this.moveSnapshotTaken = false;
    if (didMutate) {
      this.spatialGrid.rebuild(this.state.strokes);
      this.emit({ ...this.syncUndoFlags() });
      this.scheduleAutoSave();
    }
  }

  // MARK: - Selection Actions (Delete, Duplicate, Recolor, Scale, Copy/Paste)

  deleteSelected(): void {
    if (!this.hasSelection && this.state.selectionBoundary.length === 0) return;
    this.recordUndo();
    const selS = new Set(this.state.selectedStrokeIds);
    const selI = new Set(this.state.selectedImageIds);
    const selF = new Set(this.state.selectedFillIds);
    const nextStrokes = this.state.strokes.filter((s) => !selS.has(s.id));
    const nextImages = this.state.placedImages.filter((im) => !selI.has(im.id));
    const nextFills = this.state.fills.filter((f) => !selF.has(f.id));
    this.spatialGrid.rebuild(nextStrokes);
    this.resetSelectionRotationTracking();
    this.emit(
      {
        strokes: nextStrokes,
        placedImages: nextImages,
        fills: nextFills,
        selectedStrokeIds: [],
        selectedImageIds: [],
        selectedFillIds: [],
        selectionBoundary: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
  }

  duplicateSelected(): void {
    if (!this.hasSelection) return;
    this.recordUndo();
    const dx = 24;
    const dy = 24;
    const selS = new Set(this.state.selectedStrokeIds);
    const selI = new Set(this.state.selectedImageIds);
    const selF = new Set(this.state.selectedFillIds);

    const newStrokes: Stroke[] = [];
    const newStrokeIds: string[] = [];
    for (const s of this.state.strokes) {
      if (!selS.has(s.id)) continue;
      const copy: Stroke = {
        ...s,
        id: generateId(),
        points: s.points.map((p) => ({ x: p.x + dx, y: p.y + dy })),
        isEraser: false,
      };
      newStrokes.push(copy);
      newStrokeIds.push(copy.id);
    }

    const newImages: PlacedImage[] = [];
    const newImageIds: string[] = [];
    for (const img of this.state.placedImages) {
      if (!selI.has(img.id)) continue;
      const copy: PlacedImage = {
        ...img,
        id: generateId(),
        position: { x: img.position.x + dx, y: img.position.y + dy },
        size: { ...img.size },
      };
      newImages.push(copy);
      newImageIds.push(copy.id);
    }

    const newFills: FillShape[] = [];
    const newFillIds: string[] = [];
    for (const f of this.state.fills) {
      if (!selF.has(f.id)) continue;
      const copy: FillShape = {
        ...f,
        id: generateId(),
        contours: f.contours.map((loop) => loop.map((p) => ({ x: p.x + dx, y: p.y + dy }))),
      };
      newFills.push(copy);
      newFillIds.push(copy.id);
    }

    const nextStrokes = [...this.state.strokes, ...newStrokes];
    this.spatialGrid.rebuild(nextStrokes);
    if (this.selectionRotationPivot) {
      this.selectionRotationPivot = {
        x: this.selectionRotationPivot.x + dx,
        y: this.selectionRotationPivot.y + dy,
      };
    }

    this.emit(
      {
        strokes: nextStrokes,
        placedImages: [...this.state.placedImages, ...newImages],
        fills: [...this.state.fills, ...newFills],
        selectedStrokeIds: newStrokeIds,
        selectedImageIds: newImageIds,
        selectedFillIds: newFillIds,
        selectionBoundary: this.state.selectionBoundary.map((p) => ({ x: p.x + dx, y: p.y + dy })),
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
  }

  recolorSelected(color: CodableColor, presetIndex = -1): void {
    if (this.state.selectedStrokeIds.length === 0 && this.state.selectedFillIds.length === 0) return;
    this.recordUndo();
    const selS = new Set(this.state.selectedStrokeIds);
    const selF = new Set(this.state.selectedFillIds);
    const nextStrokes = this.state.strokes.map((s) =>
      selS.has(s.id) ? { ...s, color: { ...color }, presetIndex } : s
    );
    const nextFills = this.state.fills.map((f) =>
      selF.has(f.id) ? { ...f, color: { ...color }, presetIndex } : f
    );
    this.emit({ strokes: nextStrokes, fills: nextFills, ...this.syncUndoFlags() }, true);
    this.scheduleAutoSave();
  }

  transformSelected(scale = 1, rotation = 0): void {
    if (!this.hasSelection) return;
    const selS = new Set(this.state.selectedStrokeIds);
    const selI = new Set(this.state.selectedImageIds);
    const selF = new Set(this.state.selectedFillIds);
    const box = boundingBox(
      this.state.strokes.filter((s) => selS.has(s.id)),
      this.state.placedImages.filter((im) => selI.has(im.id)),
      this.state.fills.filter((f) => selF.has(f.id)),
      0
    );
    if (!box) return;
    const cx = box.x + box.width / 2;
    const cy = box.y + box.height / 2;
    const cosA = Math.cos(rotation);
    const sinA = Math.sin(rotation);
    const xform = (p: Point): Point => {
      const dx = (p.x - cx) * scale;
      const dy = (p.y - cy) * scale;
      return { x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA };
    };

    this.recordUndo();
    const nextStrokes =
      selS.size > 0
        ? this.state.strokes.map((s) =>
            selS.has(s.id)
              ? { ...s, points: s.points.map(xform), lineWidth: Math.max(0.5, s.lineWidth * scale) }
              : s
          )
        : this.state.strokes;

    const nextFills =
      selF.size > 0
        ? this.state.fills.map((f) =>
            selF.has(f.id) ? { ...f, contours: f.contours.map((loop) => loop.map(xform)) } : f
          )
        : this.state.fills;

    const nextImages =
      selI.size > 0
        ? this.state.placedImages.map((img) => {
            if (!selI.has(img.id)) return img;
            const nc = xform(imageCenter(img));
            const nw = Math.max(10, img.size.width * scale);
            const nh = Math.max(10, img.size.height * scale);
            return {
              ...img,
              position: { x: nc.x - nw / 2, y: nc.y - nh / 2 },
              size: { width: nw, height: nh },
              rotation: normalizeAngle(img.rotation + rotation),
            };
          })
        : this.state.placedImages;

    const nextBoundary = this.state.selectionBoundary.map(xform);
    const nextRot =
      rotation !== 0
        ? normalizeAngle(this.state.selectionRotationAngle + rotation)
        : this.state.selectionRotationAngle;
    if (rotation !== 0 && !this.selectionRotationPivot) {
      this.selectionRotationPivot = { x: cx, y: cy };
    }

    this.spatialGrid.rebuild(nextStrokes);
    this.emit(
      {
        strokes: nextStrokes,
        fills: nextFills,
        placedImages: nextImages,
        selectionBoundary: nextBoundary,
        selectionRotationAngle: nextRot,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
  }

  resizeSelectedImages(factor: number): void {
    if (this.state.selectedImageIds.length === 0 || factor <= 0) return;
    this.recordUndo();
    const selI = new Set(this.state.selectedImageIds);
    const nextImages = this.state.placedImages.map((img) => {
      if (!selI.has(img.id)) return img;
      const nw = Math.max(10, img.size.width * factor);
      const nh = Math.max(10, img.size.height * factor);
      return { ...img, size: { width: nw, height: nh } };
    });
    this.emit({ placedImages: nextImages, ...this.syncUndoFlags() }, true);
    this.scheduleAutoSave();
  }

  copySelected(): void {
    if (!this.hasSelection) return;
    const selS = new Set(this.state.selectedStrokeIds);
    const selI = new Set(this.state.selectedImageIds);
    const selF = new Set(this.state.selectedFillIds);
    this.internalClipboard = {
      strokes: this.state.strokes.filter((s) => selS.has(s.id)).map((s) => ({ ...s, points: s.points.map((p) => ({ ...p })) })),
      fills: this.state.fills.filter((f) => selF.has(f.id)).map((f) => ({ ...f, contours: f.contours.map((l) => l.map((p) => ({ ...p }))) })),
      placedImages: this.state.placedImages.filter((im) => selI.has(im.id)).map((im) => ({ ...im, position: { ...im.position }, size: { ...im.size } })),
      boundary: this.state.selectionBoundary.map((p) => ({ ...p })),
    };
  }

  pasteInternal(): boolean {
    const clip = this.internalClipboard;
    if (!clip) return false;
    if (clip.strokes.length === 0 && clip.fills.length === 0 && clip.placedImages.length === 0) {
      return false;
    }

    const box = boundingBox(clip.strokes, clip.placedImages, clip.fills, 0);
    let dx = 24;
    let dy = 24;
    const tap = this.lastCanvasTapLocation;
    if (
      box &&
      (tap.x !== 0 || tap.y !== 0) &&
      !(this.state.selectionBoundary.length > 0 && pointInPolygon(tap, this.state.selectionBoundary))
    ) {
      dx = tap.x - box.x;
      dy = tap.y - box.y;
    }

    this.recordUndo();
    const newStrokes = clip.strokes.map((s) => ({
      ...s,
      id: generateId(),
      points: s.points.map((p) => ({ x: p.x + dx, y: p.y + dy })),
      isEraser: false,
    }));
    const newFills = clip.fills.map((f) => ({
      ...f,
      id: generateId(),
      contours: f.contours.map((loop) => loop.map((p) => ({ x: p.x + dx, y: p.y + dy }))),
    }));
    const newImages = clip.placedImages.map((img) => ({
      ...img,
      id: generateId(),
      position: { x: img.position.x + dx, y: img.position.y + dy },
      size: { ...img.size },
    }));

    const nextStrokes = [...this.state.strokes, ...newStrokes];
    this.spatialGrid.rebuild(nextStrokes);
    this.resetSelectionRotationTracking();
    this.emit(
      {
        strokes: nextStrokes,
        fills: [...this.state.fills, ...newFills],
        placedImages: [...this.state.placedImages, ...newImages],
        selectedStrokeIds: newStrokes.map((s) => s.id),
        selectedFillIds: newFills.map((f) => f.id),
        selectedImageIds: newImages.map((im) => im.id),
        selectionBoundary: clip.boundary.map((p) => ({ x: p.x + dx, y: p.y + dy })),
        currentTool: 'select',
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
    return true;
  }

  // MARK: - Images

  addImageFromDataUrl(
    dataUrl: string,
    naturalWidth: number,
    naturalHeight: number,
    staggerIndex = 0,
    centerOverride?: Point
  ): PlacedImage {
    const maxDim = 400;
    const scaleDown = Math.min(1, maxDim / Math.max(naturalWidth, naturalHeight, 1));
    const width = Math.max(20, Math.round(naturalWidth * scaleDown));
    const height = Math.max(20, Math.round(naturalHeight * scaleDown));
    const stagger = staggerIndex * 24;
    const anchor = centerOverride ?? this.state.currentViewportCenter;
    const pos = {
      x: anchor.x - width / 2 + stagger,
      y: anchor.y - height / 2 + stagger,
    };

    this.recordUndo();
    const img: PlacedImage = {
      id: generateId(),
      position: pos,
      size: { width, height },
      imageDataBase64: stripDataUrlPrefix(dataUrl),
      rotation: 0,
    };

    this.resetSelectionRotationTracking();
    this.emit(
      {
        placedImages: [...this.state.placedImages, img],
        currentTool: 'select',
        selectedImageIds: [img.id],
        selectedStrokeIds: [],
        selectedFillIds: [],
        selectionBoundary: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
    return img;
  }

  async addImageFromBlob(blob: Blob, staggerIndex = 0, centerOverride?: Point): Promise<boolean> {
    try {
      const dataUrl = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result));
        reader.onerror = reject;
        reader.readAsDataURL(blob);
      });
      const el = await new Promise<HTMLImageElement>((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = reject;
        img.src = dataUrl;
      });
      // Downsample very large images to max 1200px (3x retina of 400pt visual size)
      let finalDataUrl = dataUrl;
      const maxPx = 1200;
      if (el.naturalWidth > maxPx || el.naturalHeight > maxPx) {
        const sc = maxPx / Math.max(el.naturalWidth, el.naturalHeight);
        const c = document.createElement('canvas');
        c.width = Math.round(el.naturalWidth * sc);
        c.height = Math.round(el.naturalHeight * sc);
        const ctx = c.getContext('2d');
        if (ctx) {
          ctx.drawImage(el, 0, 0, c.width, c.height);
          finalDataUrl = c.toDataURL('image/png');
        }
      }
      this.addImageFromDataUrl(finalDataUrl, el.naturalWidth, el.naturalHeight, staggerIndex, centerOverride);
      return true;
    } catch {
      this.setError('Could not load image file.');
      return false;
    }
  }

  // MARK: - Scenes

  addScene(name?: string): CanvasScene {
    const trimmed = name?.trim();
    const scene: CanvasScene = {
      id: generateId(),
      name: trimmed && trimmed.length > 0 ? trimmed : `Scene ${this.state.scenes.length + 1}`,
      centerX: this.state.currentViewportCenter.x,
      centerY: this.state.currentViewportCenter.y,
      scale: Math.max(this.state.currentViewportScale, 0.1),
    };
    this.emit({ scenes: [...this.state.scenes, scene], activeSceneId: scene.id });
    this.scheduleAutoSave();
    return scene;
  }

  updateSceneToCurrentView(id: string): void {
    const next = this.state.scenes.map((sc) =>
      sc.id === id
        ? {
            ...sc,
            centerX: this.state.currentViewportCenter.x,
            centerY: this.state.currentViewportCenter.y,
            scale: Math.max(this.state.currentViewportScale, 0.1),
          }
        : sc
    );
    this.emit({ scenes: next, activeSceneId: id });
    this.scheduleAutoSave();
  }

  renameScene(id: string, name: string): void {
    const trimmed = name.trim();
    if (!trimmed) return;
    this.emit({
      scenes: this.state.scenes.map((sc) => (sc.id === id ? { ...sc, name: trimmed } : sc)),
    });
    this.scheduleAutoSave();
  }

  deleteScene(id: string): void {
    const next = this.state.scenes.filter((sc) => sc.id !== id);
    this.emit({
      scenes: next,
      activeSceneId: this.state.activeSceneId === id ? next[0]?.id ?? null : this.state.activeSceneId,
    });
    this.scheduleAutoSave();
  }

  moveScene(fromIndex: number, toIndex: number): void {
    const list = [...this.state.scenes];
    if (fromIndex < 0 || fromIndex >= list.length || toIndex < 0 || toIndex >= list.length || fromIndex === toIndex) {
      return;
    }
    const [item] = list.splice(fromIndex, 1);
    list.splice(toIndex, 0, item);
    this.emit({ scenes: list });
    this.scheduleAutoSave();
  }

  navigateToScene(id: string): void {
    const sc = this.state.scenes.find((s) => s.id === id);
    if (!sc) return;
    this.emit({ activeSceneId: sc.id, pendingSceneNavigation: { ...sc } });
  }

  goToPreviousScene(): void {
    const list = this.state.scenes;
    if (list.length === 0) return;
    const idx = list.findIndex((s) => s.id === this.state.activeSceneId);
    const nextIdx = idx <= 0 ? list.length - 1 : idx - 1;
    this.navigateToScene(list[nextIdx].id);
  }

  goToNextScene(): void {
    const list = this.state.scenes;
    if (list.length === 0) return;
    const idx = list.findIndex((s) => s.id === this.state.activeSceneId);
    const nextIdx = idx < 0 || idx >= list.length - 1 ? 0 : idx + 1;
    this.navigateToScene(list[nextIdx].id);
  }

  // MARK: - Undo / Redo / Clear

  undo(): void {
    const prev = this.history.undo(this.makeSnapshot());
    if (!prev) return;
    this.spatialGrid.rebuild(prev.strokes);
    this.resetSelectionRotationTracking();
    this.emit(
      {
        strokes: prev.strokes,
        placedImages: prev.placedImages,
        fills: prev.fills,
        selectedStrokeIds: prev.selectedStrokeIds,
        selectedImageIds: prev.selectedImageIds,
        selectedFillIds: prev.selectedFillIds,
        selectionBoundary: prev.selectionBoundary,
        currentStroke: null,
        selectionLasso: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
  }

  redo(): void {
    const next = this.history.redo(this.makeSnapshot());
    if (!next) return;
    this.spatialGrid.rebuild(next.strokes);
    this.resetSelectionRotationTracking();
    this.emit(
      {
        strokes: next.strokes,
        placedImages: next.placedImages,
        fills: next.fills,
        selectedStrokeIds: next.selectedStrokeIds,
        selectedImageIds: next.selectedImageIds,
        selectedFillIds: next.selectedFillIds,
        selectionBoundary: next.selectionBoundary,
        currentStroke: null,
        selectionLasso: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
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
    this.resetSelectionRotationTracking();
    this.emit(
      {
        strokes: [],
        fills: [],
        placedImages: [],
        currentStroke: null,
        selectedStrokeIds: [],
        selectedImageIds: [],
        selectedFillIds: [],
        selectionBoundary: [],
        selectionLasso: [],
        showQuickMenu: false,
        ...this.syncUndoFlags(),
      },
      true
    );
    this.scheduleAutoSave();
  }
}

export const drawingStore = new DrawingStore(true);

export function useDrawingState(): DrawingState {
  return useSyncExternalStore(drawingStore.subscribe, drawingStore.getSnapshot);
}
