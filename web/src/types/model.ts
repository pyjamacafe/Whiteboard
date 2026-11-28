export interface Point {
  x: number;
  y: number;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CodableColor {
  r: number;
  g: number;
  b: number;
  a: number;
}

export interface Stroke {
  id: string;
  points: Point[];
  color: CodableColor;
  lineWidth: number;
  isEraser: boolean;
  presetIndex: number;
  isCatmullRom: boolean;
  isSharpie: boolean;
}

export interface FillShape {
  id: string;
  contours: Point[][];
  color: CodableColor;
  opacity: number;
  presetIndex: number;
}

export interface PlacedImage {
  id: string;
  position: Point;
  size: { width: number; height: number };
  /** Base64-encoded image bytes (PNG/JPEG) or data URL payload compatible with Swift .wb */
  imageDataBase64: string;
  /** Radians, clockwise in canvas (y-down) coordinates */
  rotation: number;
}

export interface CanvasScene {
  id: string;
  name: string;
  centerX: number;
  centerY: number;
  scale: number;
}

export type ShapeKind = 'rectangle' | 'ellipse' | 'triangle' | 'diamond' | 'line' | 'arrow';

export interface CanvasShape {
  id: string;
  kind: ShapeKind;
  start: Point;
  end: Point;
  color: CodableColor;
  presetIndex: number;
  lineWidth: number;
  isFilled: boolean;
  /** Radians, clockwise in canvas (y-down) coordinates (for 2D shapes) */
  rotation: number;
}

export interface TextLabel {
  id: string;
  text: string;
  position: Point;
  fontSize: number;
  color: CodableColor;
  presetIndex: number;
  isBold: boolean;
  /** Radians, clockwise in canvas (y-down) coordinates */
  rotation: number;
}

export interface SaveData {
  strokes: Stroke[];
  placedImages: PlacedImage[];
  fills: FillShape[];
  scenes: CanvasScene[];
  shapes?: CanvasShape[];
  textLabels?: TextLabel[];
}

export interface BoardMeta {
  id: string;
  name: string;
  created: number; // epoch ms
  modified: number; // epoch ms
  isPinned: boolean;
}

export interface BoardFolder {
  id: string;
  name: string;
  boardIds: string[];
}

export interface TrashEntry {
  id: string;
  name: string;
  deletedAt: number; // epoch ms
  data?: SaveData;
}

export type Tool = 'pen' | 'sharpie' | 'fill' | 'eraser' | 'select';

export type ToolbarDockEdge = 'top' | 'bottom' | 'left' | 'right';

export type CanvasBackground = 'none' | 'grid' | 'dots' | 'ruled';

export type FillOverlapMode = 'replace' | 'blend';

export type EraserMode = 'partial' | 'full';

export type EraseTarget = 'all' | 'pen' | 'sharpie' | 'fill';

export type ToolbarItemID =
  | 'pen'
  | 'sharpie'
  | 'fill'
  | 'eraser'
  | 'select'
  | 'scenes'
  | 'home'
  | 'undo'
  | 'redo'
  | 'clear'
  | 'copy'
  | 'paste'
  | 'importImage'
  | 'center'
  | 'fitContent'
  | 'darkMode'
  | 'warmPaper'
  | 'renameTissue'
  | 'singleTapOptions'
  | 'pencilOnly'
  | 'exportWB'
  | 'exportPNG'
  | 'exportPDF'
  | 'openFile'
  | 'help'
  | 'about';

export const ALL_TOOLBAR_ITEMS: ToolbarItemID[] = [
  'pen',
  'sharpie',
  'fill',
  'eraser',
  'select',
  'scenes',
  'home',
  'undo',
  'redo',
  'clear',
  'copy',
  'paste',
  'importImage',
  'center',
  'fitContent',
  'darkMode',
  'warmPaper',
  'renameTissue',
  'singleTapOptions',
  'pencilOnly',
  'exportWB',
  'exportPNG',
  'exportPDF',
  'openFile',
  'help',
  'about',
];

export const DEFAULT_PINNED_TOOLBAR_ITEMS: ToolbarItemID[] = [
  'pen',
  'sharpie',
  'fill',
  'eraser',
  'select',
  'scenes',
  'home',
];

export interface AppSettings {
  canvasBackground: CanvasBackground;
  revealSettingsOnSingleTap: boolean;
  pencilOnly: boolean;
  isWarmPaper: boolean;
  toolbarDockEdge: ToolbarDockEdge;
  isDarkMode: boolean;
}

export interface PenSettings {
  lightColor: CodableColor;
  darkColor: CodableColor;
  thickness: number;
  widthOptions: number[];
  lightPresets: CodableColor[];
  darkPresets: CodableColor[];
}

export interface FillSettings {
  lightColor: CodableColor;
  darkColor: CodableColor;
  opacity: number;
  opacityOptions: number[];
  gapTolerance: number;
  overlapMode: FillOverlapMode;
  lightPresets: CodableColor[];
  darkPresets: CodableColor[];
}

export interface EraserSettings {
  mode: EraserMode;
  size: number;
  eraseTarget: EraseTarget;
}

export interface ShapeSettings {
  kind: ShapeKind;
  lightColor: CodableColor;
  darkColor: CodableColor;
  lineWidth: number;
  widthOptions: number[];
  isFilled: boolean;
  lightPresets: CodableColor[];
  darkPresets: CodableColor[];
}

export interface TextSettings {
  lightColor: CodableColor;
  darkColor: CodableColor;
  fontSize: number;
  sizeOptions: number[];
  isBold: boolean;
  lightPresets: CodableColor[];
  darkPresets: CodableColor[];
}

export const DEFAULT_LIGHT_PRESETS: CodableColor[] = [
  { r: 0.05, g: 0.05, b: 0.05, a: 1 },
  { r: 0.95, g: 0.0, b: 0.1, a: 1 },
  { r: 1.0, g: 0.45, b: 0.0, a: 1 },
  { r: 1.0, g: 0.8, b: 0.0, a: 1 },
  { r: 0.0, g: 0.7, b: 0.15, a: 1 },
  { r: 0.0, g: 0.35, b: 1.0, a: 1 },
  { r: 0.55, g: 0.15, b: 1.0, a: 1 },
  { r: 0.6, g: 0.35, b: 0.1, a: 1 },
];

export const DEFAULT_DARK_PRESETS: CodableColor[] = [
  { r: 1.0, g: 1.0, b: 1.0, a: 1 },
  { r: 1.0, g: 0.3, b: 0.3, a: 1 },
  { r: 1.0, g: 0.6, b: 0.15, a: 1 },
  { r: 1.0, g: 0.9, b: 0.25, a: 1 },
  { r: 0.3, g: 1.0, b: 0.45, a: 1 },
  { r: 0.3, g: 0.6, b: 1.0, a: 1 },
  { r: 0.7, g: 0.4, b: 1.0, a: 1 },
  { r: 1.0, g: 0.4, b: 0.7, a: 1 },
];

export function colorToCss(c: CodableColor, opacityMultiplier = 1): string {
  const r = Math.round(Math.max(0, Math.min(1, c.r)) * 255);
  const g = Math.round(Math.max(0, Math.min(1, c.g)) * 255);
  const b = Math.round(Math.max(0, Math.min(1, c.b)) * 255);
  const a = Math.max(0, Math.min(1, c.a * opacityMultiplier));
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

export function colorToHex(c: CodableColor): string {
  const hex = (v: number) =>
    Math.round(Math.max(0, Math.min(1, v)) * 255)
      .toString(16)
      .padStart(2, '0');
  return `#${hex(c.r)}${hex(c.g)}${hex(c.b)}`;
}

export function hexToColor(hex: string, alpha = 1): CodableColor {
  const clean = hex.replace('#', '').trim();
  if (clean.length === 6) {
    return {
      r: parseInt(clean.slice(0, 2), 16) / 255,
      g: parseInt(clean.slice(2, 4), 16) / 255,
      b: parseInt(clean.slice(4, 6), 16) / 255,
      a: alpha,
    };
  }
  return { r: 0, g: 0, b: 0, a: alpha };
}

export function generateId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID().toUpperCase();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    .replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    })
    .toUpperCase();
}

export function defaultPenSettings(): PenSettings {
  return {
    lightColor: { ...DEFAULT_LIGHT_PRESETS[0] },
    darkColor: { ...DEFAULT_DARK_PRESETS[0] },
    thickness: 2,
    widthOptions: [2, 2.5, 3, 3.5, 4],
    lightPresets: DEFAULT_LIGHT_PRESETS.map((c) => ({ ...c })),
    darkPresets: DEFAULT_DARK_PRESETS.map((c) => ({ ...c })),
  };
}

export function defaultFillSettings(): FillSettings {
  return {
    lightColor: { ...DEFAULT_LIGHT_PRESETS[5] },
    darkColor: { ...DEFAULT_DARK_PRESETS[5] },
    opacity: 0.25,
    opacityOptions: [0.25, 0.5, 0.75, 1.0],
    gapTolerance: 2.5,
    overlapMode: 'replace',
    lightPresets: DEFAULT_LIGHT_PRESETS.map((c) => ({ ...c })),
    darkPresets: DEFAULT_DARK_PRESETS.map((c) => ({ ...c })),
  };
}

export function defaultEraserSettings(): EraserSettings {
  return {
    mode: 'full',
    size: 10,
    eraseTarget: 'all',
  };
}

export function defaultShapeSettings(): ShapeSettings {
  return {
    kind: 'rectangle',
    lightColor: { ...DEFAULT_LIGHT_PRESETS[0] },
    darkColor: { ...DEFAULT_DARK_PRESETS[0] },
    lineWidth: 2.5,
    widthOptions: [2, 2.5, 3, 3.5, 4],
    isFilled: false,
    lightPresets: DEFAULT_LIGHT_PRESETS.map((c) => ({ ...c })),
    darkPresets: DEFAULT_DARK_PRESETS.map((c) => ({ ...c })),
  };
}

export function defaultTextSettings(): TextSettings {
  return {
    lightColor: { ...DEFAULT_LIGHT_PRESETS[0] },
    darkColor: { ...DEFAULT_DARK_PRESETS[0] },
    fontSize: 22,
    sizeOptions: [16, 22, 30, 42],
    isBold: false,
    lightPresets: DEFAULT_LIGHT_PRESETS.map((c) => ({ ...c })),
    darkPresets: DEFAULT_DARK_PRESETS.map((c) => ({ ...c })),
  };
}

export function defaultAppSettings(): AppSettings {
  return {
    canvasBackground: 'grid',
    revealSettingsOnSingleTap: false,
    pencilOnly: false,
    isWarmPaper: false,
    toolbarDockEdge: 'top',
    isDarkMode: false,
  };
}
