import {
  PDFDocument,
  PDFOperator,
  PDFOperatorNames,
  PDFPage,
  degrees,
  rgb,
  pushGraphicsState,
  popGraphicsState,
  moveTo,
  lineTo,
  appendBezierCurve,
  closePath,
  stroke,
  setLineWidth,
  setLineCap,
  setLineJoin,
  LineCapStyle,
  LineJoinStyle,
  setStrokingColor,
  setFillingColor,
} from 'pdf-lib';
import type {
  CanvasScene,
  CodableColor,
  FillShape,
  PlacedImage,
  Stroke,
} from '../types/model';
import { boundingBox, smoothCatmullRom } from './geometry';
import { resolveStrokeColor } from './renderer';
import { stripDataUrlPrefix } from './wbCodec';

function toPdfRgb(c: CodableColor) {
  return rgb(
    Math.max(0, Math.min(1, c.r)),
    Math.max(0, Math.min(1, c.g)),
    Math.max(0, Math.min(1, c.b))
  );
}

function base64ToUint8Array(b64: string): Uint8Array {
  const clean = stripDataUrlPrefix(b64);
  const bin = globalThis.atob(clean);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

async function drawPageContent(
  doc: PDFDocument,
  page: PDFPage,
  params: {
    pageWidth: number;
    pageHeight: number;
    offsetX: number;
    offsetY: number;
    scale: number;
    strokes: Stroke[];
    placedImages: PlacedImage[];
    fills: FillShape[];
    penPresets: CodableColor[];
    sharpiePresets: CodableColor[];
    fillPresets: CodableColor[];
    isDarkMode: boolean;
    isWarmPaper: boolean;
  }
): Promise<void> {
  const { pageWidth, pageHeight, offsetX, offsetY, scale } = params;

  // Background fill
  const bgColor = params.isDarkMode
    ? rgb(0, 0, 0)
    : params.isWarmPaper
    ? rgb(250 / 255, 245 / 255, 235 / 255)
    : rgb(1, 1, 1);
  page.drawRectangle({ x: 0, y: 0, width: pageWidth, height: pageHeight, color: bgColor });

  // Coordinate helper: canvas (y-down) -> PDF (y-up)
  const mapX = (cx: number) => cx * scale + offsetX;
  const mapY = (cy: number) => pageHeight - (cy * scale + offsetY);

  // 1. Placed images (with rotation)
  for (const img of params.placedImages) {
    if (!img.imageDataBase64) continue;
    try {
      const bytes = base64ToUint8Array(img.imageDataBase64);
      const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8;
      const embedded = isJpeg ? await doc.embedJpg(bytes) : await doc.embedPng(bytes);
      const w = img.size.width * scale;
      const h = img.size.height * scale;
      const centerX = mapX(img.position.x + img.size.width / 2);
      const centerY = mapY(img.position.y + img.size.height / 2);
      // Clockwise in canvas y-down == negative angle in PDF y-up
      const rotRad = -(img.rotation || 0);
      const cosA = Math.cos(rotRad);
      const sinA = Math.sin(rotRad);
      // Bottom-left of image relative to center rotated by rotRad
      const blX = centerX + (-w / 2) * cosA - (-h / 2) * sinA;
      const blY = centerY + (-w / 2) * sinA + (-h / 2) * cosA;
      page.drawImage(embedded, {
        x: blX,
        y: blY,
        width: w,
        height: h,
        rotate: degrees((rotRad * 180) / Math.PI),
      });
    } catch {
      // skip invalid image bytes
    }
  }

  // 2. Vector Fills (even-odd fill rule)
  for (const f of params.fills) {
    if (f.contours.length === 0) continue;
    const base =
      f.presetIndex >= 0 && f.presetIndex < params.fillPresets.length
        ? params.fillPresets[f.presetIndex]
        : f.color;
    // Blend opacity onto background color for crisp universal PDF viewer rendering
    const bgR = params.isDarkMode ? 0 : params.isWarmPaper ? 250 / 255 : 1;
    const bgG = params.isDarkMode ? 0 : params.isWarmPaper ? 245 / 255 : 1;
    const bgB = params.isDarkMode ? 0 : params.isWarmPaper ? 235 / 255 : 1;
    const alpha = Math.max(0, Math.min(1, f.opacity * base.a));
    const blended = rgb(
      base.r * alpha + bgR * (1 - alpha),
      base.g * alpha + bgG * (1 - alpha),
      base.b * alpha + bgB * (1 - alpha)
    );

    const ops = [pushGraphicsState(), setFillingColor(blended)];
    for (const loop of f.contours) {
      if (loop.length < 3) continue;
      ops.push(moveTo(mapX(loop[0].x), mapY(loop[0].y)));
      for (let i = 1; i < loop.length; i++) {
        ops.push(lineTo(mapX(loop[i].x), mapY(loop[i].y)));
      }
      ops.push(closePath());
    }
    ops.push(PDFOperator.of(PDFOperatorNames.FillEvenOdd), popGraphicsState());
    page.pushOperators(...ops);
  }

  // 3. Vector Strokes (Pen & two-pass Sharpie)
  for (const s of params.strokes) {
    if (s.isEraser || s.points.length < 2) continue;

    const buildPathOps = () => {
      const pathOps = [];
      if (s.isCatmullRom && s.points.length >= 3) {
        const sm = smoothCatmullRom(s.points);
        pathOps.push(moveTo(mapX(sm[0].x), mapY(sm[0].y)));
        let i = 1;
        while (i + 2 < sm.length) {
          pathOps.push(
            appendBezierCurve(
              mapX(sm[i].x),
              mapY(sm[i].y),
              mapX(sm[i + 1].x),
              mapY(sm[i + 1].y),
              mapX(sm[i + 2].x),
              mapY(sm[i + 2].y)
            )
          );
          i += 3;
        }
        while (i < sm.length) {
          pathOps.push(lineTo(mapX(sm[i].x), mapY(sm[i].y)));
          i += 1;
        }
      } else {
        pathOps.push(moveTo(mapX(s.points[0].x), mapY(s.points[0].y)));
        for (let i = 1; i < s.points.length; i++) {
          pathOps.push(lineTo(mapX(s.points[i].x), mapY(s.points[i].y)));
        }
      }
      return pathOps;
    };

    const resolved = resolveStrokeColor(s, params.penPresets, params.sharpiePresets);
    if (s.isSharpie) {
      const coreColor = params.isDarkMode ? rgb(0, 0, 0) : rgb(1, 1, 1);
      page.pushOperators(
        pushGraphicsState(),
        setLineCap(LineCapStyle.Round),
        setLineJoin(LineJoinStyle.Round),
        setStrokingColor(toPdfRgb(resolved)),
        setLineWidth((s.lineWidth + 3) * scale),
        ...buildPathOps(),
        stroke(),
        setStrokingColor(coreColor),
        setLineWidth(s.lineWidth * scale),
        ...buildPathOps(),
        stroke(),
        popGraphicsState()
      );
    } else {
      page.pushOperators(
        pushGraphicsState(),
        setLineCap(LineCapStyle.Round),
        setLineJoin(LineJoinStyle.Round),
        setStrokingColor(toPdfRgb(resolved)),
        setLineWidth(s.lineWidth * scale),
        ...buildPathOps(),
        stroke(),
        popGraphicsState()
      );
    }
  }
}

export async function exportCanvasPDFBytes(params: {
  strokes: Stroke[];
  placedImages: PlacedImage[];
  fills: FillShape[];
  penPresets: CodableColor[];
  sharpiePresets: CodableColor[];
  fillPresets: CodableColor[];
  isDarkMode: boolean;
  isWarmPaper: boolean;
}): Promise<Uint8Array | null> {
  const bounds = boundingBox(params.strokes, params.placedImages, params.fills, 24);
  if (!bounds) return null;

  const doc = await PDFDocument.create();
  const pageWidth = Math.max(100, bounds.width);
  const pageHeight = Math.max(100, bounds.height);
  const page = doc.addPage([pageWidth, pageHeight]);

  await drawPageContent(doc, page, {
    ...params,
    pageWidth,
    pageHeight,
    offsetX: -bounds.x,
    offsetY: -bounds.y,
    scale: 1,
  });

  return doc.save();
}

export async function exportScenesPDFBytes(params: {
  scenes: CanvasScene[];
  strokes: Stroke[];
  placedImages: PlacedImage[];
  fills: FillShape[];
  penPresets: CodableColor[];
  sharpiePresets: CodableColor[];
  fillPresets: CodableColor[];
  isDarkMode: boolean;
  isWarmPaper: boolean;
}): Promise<Uint8Array | null> {
  if (params.scenes.length === 0) return null;
  const doc = await PDFDocument.create();
  const pageWidth = 1200;
  const pageHeight = 900;

  for (const scene of params.scenes) {
    const page = doc.addPage([pageWidth, pageHeight]);
    const s = Math.min(Math.max(scene.scale, 0.3), 5.0);
    await drawPageContent(doc, page, {
      ...params,
      pageWidth,
      pageHeight,
      offsetX: pageWidth / 2 - scene.centerX * s,
      offsetY: pageHeight / 2 - scene.centerY * s,
      scale: s,
    });
  }

  return doc.save();
}

export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
