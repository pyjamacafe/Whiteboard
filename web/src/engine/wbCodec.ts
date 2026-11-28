import type {
  CanvasScene,
  CodableColor,
  FillShape,
  PlacedImage,
  Point,
  SaveData,
  Stroke,
} from '../types/model';
import { generateId } from '../types/model';

/**
 * Portable `.wb` JSON codec 100% compatible with macOS & iPadOS Tissue Box (`SaveData`).
 *
 * Swift's `JSONEncoder` encodes:
 * - `CGPoint` as `[x, y]` (2-element array)
 * - `CodablePoint` (`PlacedImage.position`, `PlacedImage.size`) as `{ "x": ..., "y": ... }`
 * - `Data` (`PlacedImage.imageData`) as standard Base64 string
 * - `CodableColor` as `{ "r": ..., "g": ..., "b": ..., "a": ... }`
 *
 * We encode in that exact Swift-compatible format and accept both `[x, y]` and `{x, y}` on decode.
 */

function decodePoint(raw: unknown): Point {
  if (Array.isArray(raw) && raw.length >= 2) {
    return { x: Number(raw[0]) || 0, y: Number(raw[1]) || 0 };
  }
  if (raw && typeof raw === 'object') {
    const obj = raw as Record<string, unknown>;
    return { x: Number(obj.x) || 0, y: Number(obj.y) || 0 };
  }
  return { x: 0, y: 0 };
}

function encodeCGPoint(p: Point): [number, number] {
  return [p.x, p.y];
}

function decodeColor(raw: unknown): CodableColor {
  if (raw && typeof raw === 'object') {
    const obj = raw as Record<string, unknown>;
    return {
      r: Number(obj.r) || 0,
      g: Number(obj.g) || 0,
      b: Number(obj.b) || 0,
      a: obj.a !== undefined ? Number(obj.a) : 1,
    };
  }
  return { r: 0, g: 0, b: 0, a: 1 };
}

export function encodeWBJson(data: SaveData): string {
  const payload = {
    strokes: data.strokes.map((s) => ({
      id: s.id,
      points: s.points.map(encodeCGPoint),
      color: s.color,
      lineWidth: s.lineWidth,
      isEraser: s.isEraser,
      presetIndex: s.presetIndex,
      isCatmullRom: s.isCatmullRom,
      isSharpie: s.isSharpie,
    })),
    placedImages: data.placedImages.map((img) => ({
      id: img.id,
      position: { x: img.position.x, y: img.position.y },
      size: { x: img.size.width, y: img.size.height },
      imageData: stripDataUrlPrefix(img.imageDataBase64),
      rotation: img.rotation || 0,
    })),
    fills: data.fills.map((f) => ({
      id: f.id,
      contours: f.contours.map((loop) => loop.map(encodeCGPoint)),
      color: f.color,
      opacity: f.opacity,
      presetIndex: f.presetIndex,
    })),
    scenes: data.scenes.map((sc) => ({
      id: sc.id,
      name: sc.name,
      centerX: sc.centerX,
      centerY: sc.centerY,
      scale: sc.scale,
    })),
  };
  return JSON.stringify(payload);
}

export function decodeWBJson(jsonText: string): SaveData {
  const raw = JSON.parse(jsonText) as Record<string, unknown>;
  if (!raw || typeof raw !== 'object') {
    throw new Error('Invalid .wb file format.');
  }

  const rawStrokes = Array.isArray(raw.strokes) ? raw.strokes : [];
  const strokes: Stroke[] = rawStrokes.map((item) => {
    const o = item as Record<string, unknown>;
    const pts = Array.isArray(o.points) ? o.points.map(decodePoint) : [];
    return {
      id: typeof o.id === 'string' ? o.id : generateId(),
      points: pts,
      color: decodeColor(o.color),
      lineWidth: typeof o.lineWidth === 'number' ? o.lineWidth : 2,
      isEraser: Boolean(o.isEraser),
      presetIndex: typeof o.presetIndex === 'number' ? o.presetIndex : -1,
      isCatmullRom: Boolean(o.isCatmullRom),
      isSharpie: Boolean(o.isSharpie),
    };
  });

  const rawImages = Array.isArray(raw.placedImages) ? raw.placedImages : [];
  const placedImages: PlacedImage[] = rawImages.map((item) => {
    const o = item as Record<string, unknown>;
    const pos = decodePoint(o.position);
    const sz = decodePoint(o.size);
    const rawData = typeof o.imageData === 'string' ? o.imageData : '';
    return {
      id: typeof o.id === 'string' ? o.id : generateId(),
      position: pos,
      size: { width: sz.x, height: sz.y },
      imageDataBase64: stripDataUrlPrefix(rawData),
      rotation: typeof o.rotation === 'number' && Number.isFinite(o.rotation) ? o.rotation : 0,
    };
  });

  const rawFills = Array.isArray(raw.fills) ? raw.fills : [];
  const fills: FillShape[] = rawFills.map((item) => {
    const o = item as Record<string, unknown>;
    const rawContours = Array.isArray(o.contours) ? o.contours : [];
    const contours = rawContours.map((loop) =>
      Array.isArray(loop) ? loop.map(decodePoint) : []
    );
    return {
      id: typeof o.id === 'string' ? o.id : generateId(),
      contours,
      color: decodeColor(o.color),
      opacity: typeof o.opacity === 'number' ? o.opacity : 1.0,
      presetIndex: typeof o.presetIndex === 'number' ? o.presetIndex : -1,
    };
  });

  const rawScenes = Array.isArray(raw.scenes) ? raw.scenes : [];
  const scenes: CanvasScene[] = rawScenes.map((item) => {
    const o = item as Record<string, unknown>;
    return {
      id: typeof o.id === 'string' ? o.id : generateId(),
      name: typeof o.name === 'string' ? o.name : 'Scene',
      centerX: typeof o.centerX === 'number' ? o.centerX : 0,
      centerY: typeof o.centerY === 'number' ? o.centerY : 0,
      scale: typeof o.scale === 'number' && o.scale > 0 ? o.scale : 1,
    };
  });

  return { strokes, placedImages, fills, scenes };
}

export function stripDataUrlPrefix(b64: string): string {
  const idx = b64.indexOf(',');
  if (b64.startsWith('data:') && idx >= 0) {
    return b64.slice(idx + 1);
  }
  return b64;
}

export function imageBase64ToDataUrl(b64: string): string {
  if (b64.startsWith('data:')) return b64;
  // Detect JPEG magic (/9j/) vs WebP (UklGR) vs PNG default
  if (b64.startsWith('/9j/')) return `data:image/jpeg;base64,${b64}`;
  if (b64.startsWith('UklGR')) return `data:image/webp;base64,${b64}`;
  return `data:image/png;base64,${b64}`;
}
