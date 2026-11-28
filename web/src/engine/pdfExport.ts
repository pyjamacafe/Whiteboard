import {
  PDFDocument,
  PDFOperator,
  PDFOperatorNames,
  PDFPage,
  StandardFonts,
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
  CanvasShape,
  CodableColor,
  FillShape,
  PlacedImage,
  Point,
  Stroke,
  TextLabel,
} from '../types/model';
import {
  boundingBox,
  isLineLikeShape,
  rotatePoint,
  shapeCenter,
  shapeRect,
  smoothCatmullRom,
  textLabelCenter,
} from './geometry';
import { resolveShapeColor, resolveStrokeColor, resolveTextColor } from './renderer';
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
    shapes?: CanvasShape[];
    textLabels?: TextLabel[];
    penPresets: CodableColor[];
    sharpiePresets: CodableColor[];
    fillPresets: CodableColor[];
    shapePresets?: CodableColor[];
    textPresets?: CodableColor[];
    isDarkMode: boolean;
    isWarmPaper: boolean;
  }
): Promise<void> {
  const { pageWidth, pageHeight, offsetX, offsetY, scale } = params;
  const shapes = params.shapes ?? [];
  const textLabels = params.textLabels ?? [];
  const shapePresets = params.shapePresets ?? params.penPresets;
  const textPresets = params.textPresets ?? params.penPresets;
  const bgR = params.isDarkMode ? 0 : params.isWarmPaper ? 250 / 255 : 1;
  const bgG = params.isDarkMode ? 0 : params.isWarmPaper ? 245 / 255 : 1;
  const bgB = params.isDarkMode ? 0 : params.isWarmPaper ? 235 / 255 : 1;

  // Background fill
  const bgColor = rgb(bgR, bgG, bgB);
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

  // 3. Vector Shapes (Rectangle, Ellipse, Triangle, Diamond, Line, Arrow)
  for (const sh of shapes) {
    const resolved = resolveShapeColor(sh, shapePresets);
    const strokePdfColor = toPdfRgb(resolved);
    const fillAlpha = 0.2 * Math.max(0, Math.min(1, resolved.a));
    const blendedFill = rgb(
      resolved.r * fillAlpha + bgR * (1 - fillAlpha),
      resolved.g * fillAlpha + bgG * (1 - fillAlpha),
      resolved.b * fillAlpha + bgB * (1 - fillAlpha)
    );

    if (isLineLikeShape(sh.kind)) {
      const pathOps = [
        moveTo(mapX(sh.start.x), mapY(sh.start.y)),
        lineTo(mapX(sh.end.x), mapY(sh.end.y)),
      ];
      if (sh.kind === 'arrow') {
        const dx = sh.end.x - sh.start.x;
        const dy = sh.end.y - sh.start.y;
        const len = Math.hypot(dx, dy);
        if (len > 1) {
          const headLen = Math.min(Math.max(12, sh.lineWidth * 4.5), len * 0.45);
          const angle = Math.atan2(dy, dx);
          const spread = Math.PI / 6;
          const lx = sh.end.x - headLen * Math.cos(angle - spread);
          const ly = sh.end.y - headLen * Math.sin(angle - spread);
          const rx = sh.end.x - headLen * Math.cos(angle + spread);
          const ry = sh.end.y - headLen * Math.sin(angle + spread);
          pathOps.push(
            moveTo(mapX(lx), mapY(ly)),
            lineTo(mapX(sh.end.x), mapY(sh.end.y)),
            lineTo(mapX(rx), mapY(ry))
          );
        }
      }
      page.pushOperators(
        pushGraphicsState(),
        setLineCap(LineCapStyle.Round),
        setLineJoin(LineJoinStyle.Round),
        setStrokingColor(strokePdfColor),
        setLineWidth(sh.lineWidth * scale),
        ...pathOps,
        stroke(),
        popGraphicsState()
      );
      continue;
    }

    const r = shapeRect(sh);
    if (r.width < 0.5 && r.height < 0.5) continue;
    const center = shapeCenter(sh);
    const rot = sh.rotation || 0;
    const xformPt = (p: Point): Point => (rot ? rotatePoint(p, center, rot) : p);

    const buildShapeOps = (): PDFOperator[] => {
      if (sh.kind === 'ellipse') {
        const cx = r.x + r.width / 2;
        const cy = r.y + r.height / 2;
        const rx = r.width / 2;
        const ry = r.height / 2;
        const k = 0.5522847498;
        const kx = rx * k;
        const ky = ry * k;
        const p0 = xformPt({ x: cx, y: cy - ry });
        const p1 = xformPt({ x: cx + rx, y: cy });
        const p2 = xformPt({ x: cx, y: cy + ry });
        const p3 = xformPt({ x: cx - rx, y: cy });
        const c0a = xformPt({ x: cx + kx, y: cy - ry });
        const c0b = xformPt({ x: cx + rx, y: cy - ky });
        const c1a = xformPt({ x: cx + rx, y: cy + ky });
        const c1b = xformPt({ x: cx + kx, y: cy + ry });
        const c2a = xformPt({ x: cx - kx, y: cy + ry });
        const c2b = xformPt({ x: cx - rx, y: cy + ky });
        const c3a = xformPt({ x: cx - rx, y: cy - ky });
        const c3b = xformPt({ x: cx - kx, y: cy - ry });
        return [
          moveTo(mapX(p0.x), mapY(p0.y)),
          appendBezierCurve(mapX(c0a.x), mapY(c0a.y), mapX(c0b.x), mapY(c0b.y), mapX(p1.x), mapY(p1.y)),
          appendBezierCurve(mapX(c1a.x), mapY(c1a.y), mapX(c1b.x), mapY(c1b.y), mapX(p2.x), mapY(p2.y)),
          appendBezierCurve(mapX(c2a.x), mapY(c2a.y), mapX(c2b.x), mapY(c2b.y), mapX(p3.x), mapY(p3.y)),
          appendBezierCurve(mapX(c3a.x), mapY(c3a.y), mapX(c3b.x), mapY(c3b.y), mapX(p0.x), mapY(p0.y)),
          closePath(),
        ];
      }
      let pts: Point[];
      if (sh.kind === 'rectangle') {
        pts = [
          { x: r.x, y: r.y },
          { x: r.x + r.width, y: r.y },
          { x: r.x + r.width, y: r.y + r.height },
          { x: r.x, y: r.y + r.height },
        ];
      } else if (sh.kind === 'triangle') {
        pts = [
          { x: r.x + r.width / 2, y: r.y },
          { x: r.x + r.width, y: r.y + r.height },
          { x: r.x, y: r.y + r.height },
        ];
      } else {
        pts = [
          { x: r.x + r.width / 2, y: r.y },
          { x: r.x + r.width, y: r.y + r.height / 2 },
          { x: r.x + r.width / 2, y: r.y + r.height },
          { x: r.x, y: r.y + r.height / 2 },
        ];
      }
      const mapped = pts.map(xformPt);
      const ops: PDFOperator[] = [moveTo(mapX(mapped[0].x), mapY(mapped[0].y))];
      for (let i = 1; i < mapped.length; i++) {
        ops.push(lineTo(mapX(mapped[i].x), mapY(mapped[i].y)));
      }
      ops.push(closePath());
      return ops;
    };

    const shapeOps = buildShapeOps();
    if (sh.isFilled) {
      page.pushOperators(
        pushGraphicsState(),
        setFillingColor(blendedFill),
        ...shapeOps,
        PDFOperator.of(PDFOperatorNames.FillNonZero),
        popGraphicsState()
      );
    }
    page.pushOperators(
      pushGraphicsState(),
      setLineCap(LineCapStyle.Round),
      setLineJoin(LineJoinStyle.Round),
      setStrokingColor(strokePdfColor),
      setLineWidth(sh.lineWidth * scale),
      ...shapeOps,
      stroke(),
      popGraphicsState()
    );
  }

  // 4. Vector Strokes (Pen & two-pass Sharpie)
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

  // 5. Selectable Vector Text Labels
  if (textLabels.length > 0) {
    const regularFont = await doc.embedFont(StandardFonts.Helvetica);
    const boldFont = await doc.embedFont(StandardFonts.HelveticaBold);
    for (const lbl of textLabels) {
      if (!lbl.text) continue;
      const font = lbl.isBold ? boldFont : regularFont;
      const color = toPdfRgb(resolveTextColor(lbl, textPresets));
      const fontSize = lbl.fontSize * scale;
      const lineHeight = lbl.fontSize * 1.28;
      const lines = lbl.text.split('\n');
      const center = textLabelCenter(lbl);
      const rot = lbl.rotation || 0;
      const pdfRotDeg = (-rot * 180) / Math.PI;

      for (let i = 0; i < lines.length; i++) {
        const safeLine = lines[i].replace(/[^\x20-\xFF]/g, '?');
        if (!safeLine) continue;
        // Baseline point in canvas y-down coords (approx 0.85 * fontSize below top of line)
        const baseCanvas: Point = {
          x: lbl.position.x + 4,
          y: lbl.position.y + 2 + i * lineHeight + lbl.fontSize * 0.88,
        };
        const pt = rot ? rotatePoint(baseCanvas, center, rot) : baseCanvas;
        try {
          page.drawText(safeLine, {
            x: mapX(pt.x),
            y: mapY(pt.y),
            size: fontSize,
            font,
            color,
            rotate: degrees(pdfRotDeg),
          });
        } catch {
          // ignore unencodable glyphs
        }
      }
    }
  }
}

export async function exportCanvasPDFBytes(params: {
  strokes: Stroke[];
  placedImages: PlacedImage[];
  fills: FillShape[];
  shapes?: CanvasShape[];
  textLabels?: TextLabel[];
  penPresets: CodableColor[];
  sharpiePresets: CodableColor[];
  fillPresets: CodableColor[];
  shapePresets?: CodableColor[];
  textPresets?: CodableColor[];
  isDarkMode: boolean;
  isWarmPaper: boolean;
}): Promise<Uint8Array | null> {
  const bounds = boundingBox(
    params.strokes,
    params.placedImages,
    params.fills,
    24,
    params.shapes ?? [],
    params.textLabels ?? []
  );
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
  shapes?: CanvasShape[];
  textLabels?: TextLabel[];
  penPresets: CodableColor[];
  sharpiePresets: CodableColor[];
  fillPresets: CodableColor[];
  shapePresets?: CodableColor[];
  textPresets?: CodableColor[];
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
