import type {
  CanvasBackground,
  CanvasScene,
  CanvasShape,
  CodableColor,
  FillShape,
  PlacedImage,
  Stroke,
  TextLabel,
} from '../types/model';
import { colorToCss } from '../types/model';
import {
  boundingBox,
  isLineLikeShape,
  shapeCenter,
  shapeRect,
  textLabelCenter,
} from './geometry';
import { traceStrokeToContext } from './floodFill';
import {
  MARKDOWN_CODE_PADDING_X,
  MARKDOWN_HORIZONTAL_INSET,
  MARKDOWN_LINE_HEIGHT_MULT,
  MARKDOWN_VERTICAL_INSET,
  measureMarkdownPrefixWidth,
  monospaceCanvasFont,
  parseMarkdown,
} from './markdown';
import { imageBase64ToDataUrl } from './wbCodec';

export function resolveStrokeColor(
  stroke: Stroke,
  penPresets: CodableColor[],
  sharpiePresets: CodableColor[]
): CodableColor {
  if (stroke.presetIndex >= 0) {
    if (stroke.isSharpie) {
      if (stroke.presetIndex < sharpiePresets.length) return sharpiePresets[stroke.presetIndex];
    } else if (stroke.presetIndex < penPresets.length) {
      return penPresets[stroke.presetIndex];
    }
  }
  return stroke.color;
}

export function resolveFillColor(fill: FillShape, fillPresets: CodableColor[]): string {
  const base =
    fill.presetIndex >= 0 && fill.presetIndex < fillPresets.length
      ? fillPresets[fill.presetIndex]
      : fill.color;
  return colorToCss(base, fill.opacity);
}

export function resolveShapeColor(shape: CanvasShape, shapePresets: CodableColor[]): CodableColor {
  if (shape.presetIndex >= 0 && shape.presetIndex < shapePresets.length) {
    return shapePresets[shape.presetIndex];
  }
  return shape.color;
}

export function resolveTextColor(label: TextLabel, textPresets: CodableColor[]): CodableColor {
  if (label.presetIndex >= 0 && label.presetIndex < textPresets.length) {
    return textPresets[label.presetIndex];
  }
  return label.color;
}

export function drawCanvasShape(
  ctx: CanvasRenderingContext2D,
  shape: CanvasShape,
  shapePresets: CodableColor[]
): void {
  const resolved = resolveShapeColor(shape, shapePresets);
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.lineWidth = shape.lineWidth;
  ctx.strokeStyle = colorToCss(resolved);

  if (isLineLikeShape(shape.kind)) {
    ctx.beginPath();
    ctx.moveTo(shape.start.x, shape.start.y);
    ctx.lineTo(shape.end.x, shape.end.y);
    if (shape.kind === 'arrow') {
      const dx = shape.end.x - shape.start.x;
      const dy = shape.end.y - shape.start.y;
      const len = Math.hypot(dx, dy);
      if (len > 1) {
        const headLen = Math.min(Math.max(12, shape.lineWidth * 4.5), len * 0.45);
        const angle = Math.atan2(dy, dx);
        const spread = Math.PI / 6;
        ctx.moveTo(
          shape.end.x - headLen * Math.cos(angle - spread),
          shape.end.y - headLen * Math.sin(angle - spread)
        );
        ctx.lineTo(shape.end.x, shape.end.y);
        ctx.lineTo(
          shape.end.x - headLen * Math.cos(angle + spread),
          shape.end.y - headLen * Math.sin(angle + spread)
        );
      }
    }
    ctx.stroke();
    ctx.restore();
    return;
  }

  const r = shapeRect(shape);
  if (r.width < 0.5 && r.height < 0.5) {
    ctx.restore();
    return;
  }
  if (shape.rotation) {
    const c = shapeCenter(shape);
    ctx.translate(c.x, c.y);
    ctx.rotate(shape.rotation);
    ctx.translate(-c.x, -c.y);
  }

  ctx.beginPath();
  if (shape.kind === 'rectangle') {
    ctx.rect(r.x, r.y, r.width, r.height);
  } else if (shape.kind === 'ellipse') {
    ctx.ellipse(
      r.x + r.width / 2,
      r.y + r.height / 2,
      Math.max(0.5, r.width / 2),
      Math.max(0.5, r.height / 2),
      0,
      0,
      Math.PI * 2
    );
  } else if (shape.kind === 'triangle') {
    ctx.moveTo(r.x + r.width / 2, r.y);
    ctx.lineTo(r.x + r.width, r.y + r.height);
    ctx.lineTo(r.x, r.y + r.height);
    ctx.closePath();
  } else if (shape.kind === 'diamond') {
    ctx.moveTo(r.x + r.width / 2, r.y);
    ctx.lineTo(r.x + r.width, r.y + r.height / 2);
    ctx.lineTo(r.x + r.width / 2, r.y + r.height);
    ctx.lineTo(r.x, r.y + r.height / 2);
    ctx.closePath();
  }

  if (shape.isFilled) {
    ctx.fillStyle = colorToCss(resolved, 0.2);
    ctx.fill();
  }
  ctx.stroke();
  ctx.restore();
}

function traceRoundedRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
): void {
  const rad = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rad, y);
  ctx.lineTo(x + w - rad, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + rad);
  ctx.lineTo(x + w, y + h - rad);
  ctx.quadraticCurveTo(x + w, y + h, x + w - rad, y + h);
  ctx.lineTo(x + rad, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - rad);
  ctx.lineTo(x, y + rad);
  ctx.quadraticCurveTo(x, y, x + rad, y);
  ctx.closePath();
}

export function drawTextLabel(
  ctx: CanvasRenderingContext2D,
  label: TextLabel,
  textPresets: CodableColor[]
): void {
  if (!label.text) return;
  const resolved = resolveTextColor(label, textPresets);
  const parsed = parseMarkdown(label.text);
  const fullColor = colorToCss(resolved);
  const mutedColor = colorToCss(resolved, 0.75);
  const barColor = colorToCss(resolved, 0.45);
  const codeBgColor = colorToCss(resolved, 0.12);
  const checkBgColor = colorToCss(resolved, 0.18);

  ctx.save();
  if (label.rotation) {
    const c = textLabelCenter(label);
    ctx.translate(c.x, c.y);
    ctx.rotate(label.rotation);
    ctx.translate(-c.x, -c.y);
  }

  ctx.textBaseline = 'top';
  ctx.textAlign = 'left';

  const measureText = (text: string, size: number, bold: boolean, italic: boolean): number => {
    ctx.font = monospaceCanvasFont(size, bold, italic);
    return ctx.measureText(text).width;
  };

  let cursorY = label.position.y + MARKDOWN_VERTICAL_INSET;
  const startX = label.position.x + MARKDOWN_HORIZONTAL_INSET;

  for (const line of parsed) {
    const lineFontSize = label.fontSize * line.fontScale;
    const lineHeight = lineFontSize * MARKDOWN_LINE_HEIGHT_MULT;
    const prefixW = measureMarkdownPrefixWidth(line.kind, lineFontSize, measureText, label.isBold);

    // Draw block prefix decoration
    if (line.kind.type === 'blockquote') {
      ctx.fillStyle = barColor;
      traceRoundedRect(
        ctx,
        startX + 2,
        cursorY + lineFontSize * 0.12,
        Math.max(2, lineFontSize * 0.12),
        lineHeight * 0.78,
        1.5
      );
      ctx.fill();
    } else if (line.kind.type === 'bullet') {
      const bx = startX + line.kind.indentLevel * lineFontSize * 1.1 + lineFontSize * 0.35;
      const by = cursorY + lineFontSize * 0.62;
      const r = Math.max(2, lineFontSize * 0.14);
      ctx.fillStyle = fullColor;
      ctx.beginPath();
      ctx.arc(bx, by, r, 0, Math.PI * 2);
      ctx.fill();
    } else if (line.kind.type === 'numbered') {
      const mx = startX + line.kind.indentLevel * lineFontSize * 1.1;
      ctx.font = monospaceCanvasFont(lineFontSize, label.isBold, false);
      ctx.fillStyle = fullColor;
      ctx.fillText(line.kind.marker, mx, cursorY);
    } else if (line.kind.type === 'checklist') {
      const boxSize = Math.max(10, lineFontSize * 0.76);
      const bx = startX + line.kind.indentLevel * lineFontSize * 1.1 + lineFontSize * 0.1;
      const by = cursorY + (lineFontSize * 1.15 - boxSize) / 2;
      traceRoundedRect(ctx, bx, by, boxSize, boxSize, Math.max(2, boxSize * 0.2));
      if (line.kind.checked) {
        ctx.fillStyle = checkBgColor;
        ctx.fill();
      }
      ctx.strokeStyle = fullColor;
      ctx.lineWidth = Math.max(1.2, lineFontSize * 0.08);
      ctx.stroke();
      if (line.kind.checked) {
        ctx.save();
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.beginPath();
        ctx.moveTo(bx + boxSize * 0.22, by + boxSize * 0.52);
        ctx.lineTo(bx + boxSize * 0.44, by + boxSize * 0.74);
        ctx.lineTo(bx + boxSize * 0.80, by + boxSize * 0.28);
        ctx.stroke();
        ctx.restore();
      }
    }

    // Draw inline spans
    let cursorX = startX + prefixW;
    const isCheckedChecklist = line.kind.type === 'checklist' && line.kind.checked;
    const isMuted = line.kind.type === 'blockquote' || isCheckedChecklist;

    for (const span of line.spans) {
      const isBold = label.isBold || line.forcesBold || span.isBold;
      const isItalic = line.defaultsItalic || span.isItalic;
      ctx.font = monospaceCanvasFont(lineFontSize, isBold, isItalic);
      const runW = ctx.measureText(span.text).width;

      if (span.isCode) {
        ctx.fillStyle = codeBgColor;
        traceRoundedRect(
          ctx,
          cursorX,
          cursorY + lineFontSize * 0.04,
          runW + MARKDOWN_CODE_PADDING_X * 2,
          lineFontSize * 1.12,
          4
        );
        ctx.fill();
        cursorX += MARKDOWN_CODE_PADDING_X;
      }

      const ink = isMuted ? mutedColor : fullColor;
      ctx.fillStyle = ink;
      ctx.fillText(span.text, cursorX, cursorY);

      if (span.isUnderline) {
        ctx.save();
        ctx.strokeStyle = ink;
        ctx.lineWidth = Math.max(1, lineFontSize * 0.065);
        const uy = cursorY + lineFontSize * 1.06;
        ctx.beginPath();
        ctx.moveTo(cursorX, uy);
        ctx.lineTo(cursorX + runW, uy);
        ctx.stroke();
        ctx.restore();
      }

      if (span.isStrikethrough || isCheckedChecklist) {
        ctx.save();
        ctx.strokeStyle = ink;
        ctx.lineWidth = Math.max(1, lineFontSize * 0.065);
        const sy = cursorY + lineFontSize * 0.56;
        ctx.beginPath();
        ctx.moveTo(cursorX, sy);
        ctx.lineTo(cursorX + runW, sy);
        ctx.stroke();
        ctx.restore();
      }

      cursorX += runW + (span.isCode ? MARKDOWN_CODE_PADDING_X : 0);
    }

    cursorY += lineHeight;
  }

  ctx.restore();
}

export function canvasBackgroundFill(isDarkMode: boolean, isWarmPaper: boolean): string {
  if (isDarkMode) return '#000000';
  if (isWarmPaper) return 'rgb(250, 245, 235)';
  return '#ffffff';
}

export function drawBackgroundGrid(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  background: CanvasBackground,
  isDarkMode: boolean,
  isWarmPaper: boolean,
  offsetX: number,
  offsetY: number,
  scale: number
): void {
  ctx.fillStyle = canvasBackgroundFill(isDarkMode, isWarmPaper);
  ctx.fillRect(0, 0, width, height);

  if (background === 'none') return;

  const spacing = 40 * Math.max(scale, 0.1);
  if (spacing < 6) return;

  const strokeColor = isDarkMode
    ? 'rgba(255, 255, 255, 0.08)'
    : isWarmPaper
    ? 'rgba(130, 105, 70, 0.11)'
    : 'rgba(0, 0, 0, 0.08)';

  const startX = ((offsetX % spacing) + spacing) % spacing;
  const startY = ((offsetY % spacing) + spacing) % spacing;

  ctx.save();
  if (background === 'dots') {
    ctx.fillStyle = isDarkMode
      ? 'rgba(255, 255, 255, 0.18)'
      : isWarmPaper
      ? 'rgba(130, 105, 70, 0.22)'
      : 'rgba(0, 0, 0, 0.18)';
    const r = Math.max(1.1, Math.min(2.0, scale * 1.4));
    for (let x = startX; x < width; x += spacing) {
      for (let y = startY; y < height; y += spacing) {
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  } else if (background === 'ruled') {
    ctx.strokeStyle = strokeColor;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let y = startY; y < height; y += spacing) {
      const py = Math.round(y) + 0.5;
      ctx.moveTo(0, py);
      ctx.lineTo(width, py);
    }
    ctx.stroke();
  } else if (background === 'grid') {
    ctx.strokeStyle = strokeColor;
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    for (let x = startX; x < width; x += spacing) {
      const px = Math.round(x) + 0.5;
      ctx.moveTo(px, 0);
      ctx.lineTo(px, height);
    }
    for (let y = startY; y < height; y += spacing) {
      const py = Math.round(y) + 0.5;
      ctx.moveTo(0, py);
      ctx.lineTo(width, py);
    }
    ctx.stroke();
  }
  ctx.restore();
}

export function drawFillShape(
  ctx: CanvasRenderingContext2D,
  fill: FillShape,
  fillPresets: CodableColor[]
): void {
  if (fill.contours.length === 0) return;
  ctx.save();
  ctx.fillStyle = resolveFillColor(fill, fillPresets);
  ctx.beginPath();
  for (const loop of fill.contours) {
    if (loop.length < 3) continue;
    ctx.moveTo(loop[0].x, loop[0].y);
    for (let i = 1; i < loop.length; i++) {
      ctx.lineTo(loop[i].x, loop[i].y);
    }
    ctx.closePath();
  }
  ctx.fill('evenodd');
  ctx.restore();
}

export function drawStroke(
  ctx: CanvasRenderingContext2D,
  stroke: Stroke,
  penPresets: CodableColor[],
  sharpiePresets: CodableColor[],
  isDarkMode: boolean,
  eraserWidthOverride?: number
): void {
  if (stroke.points.length < 2) return;
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  ctx.beginPath();
  traceStrokeToContext(ctx, stroke);

  if (stroke.isEraser) {
    ctx.strokeStyle = 'rgba(255, 59, 48, 0.25)';
    ctx.lineWidth = eraserWidthOverride ?? stroke.lineWidth;
    ctx.stroke();
  } else if (stroke.isSharpie) {
    const glow = resolveStrokeColor(stroke, penPresets, sharpiePresets);
    ctx.strokeStyle = colorToCss(glow);
    ctx.lineWidth = stroke.lineWidth + 3;
    ctx.stroke();

    ctx.strokeStyle = isDarkMode ? '#000000' : '#ffffff';
    ctx.lineWidth = stroke.lineWidth;
    ctx.stroke();
  } else {
    const c = resolveStrokeColor(stroke, penPresets, sharpiePresets);
    ctx.strokeStyle = colorToCss(c);
    ctx.lineWidth = stroke.lineWidth;
    ctx.stroke();
  }
  ctx.restore();
}

export function drawPlacedImage(
  ctx: CanvasRenderingContext2D,
  img: PlacedImage,
  htmlImg: HTMLImageElement | ImageBitmap
): void {
  const { width, height } = img.size;
  if (width <= 0 || height <= 0) return;
  ctx.save();
  const cx = img.position.x + width / 2;
  const cy = img.position.y + height / 2;
  ctx.translate(cx, cy);
  if (img.rotation) {
    ctx.rotate(img.rotation);
  }
  ctx.drawImage(htmlImg, -width / 2, -height / 2, width, height);
  ctx.restore();
}

export function loadHtmlImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = (e) => reject(e);
    img.src = src;
  });
}

/**
 * Renders transparent high-DPI PNG data URL matching StrokeRenderer.pngData.
 */
export async function renderPNGBlob(params: {
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
  scale?: number;
}): Promise<Blob | null> {
  const shapes = params.shapes ?? [];
  const textLabels = params.textLabels ?? [];
  const bounds = boundingBox(params.strokes, params.placedImages, params.fills, 24, shapes, textLabels);
  if (!bounds) return null;

  const exportScale = Math.min(params.scale ?? 3, 8192 / Math.max(bounds.width, bounds.height));
  const w = Math.max(1, Math.round(bounds.width * exportScale));
  const h = Math.max(1, Math.round(bounds.height * exportScale));
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;

  ctx.save();
  ctx.scale(exportScale, exportScale);
  ctx.translate(-bounds.x, -bounds.y);

  for (const img of params.placedImages) {
    try {
      const el = await loadHtmlImage(imageBase64ToDataUrl(img.imageDataBase64));
      drawPlacedImage(ctx, img, el);
    } catch {
      // skip undecodable image
    }
  }
  for (const f of params.fills) {
    drawFillShape(ctx, f, params.fillPresets);
  }
  const shapePresets = params.shapePresets ?? params.penPresets;
  const textPresets = params.textPresets ?? params.penPresets;
  for (const sh of shapes) {
    drawCanvasShape(ctx, sh, shapePresets);
  }
  for (const s of params.strokes) {
    if (!s.isEraser) {
      drawStroke(ctx, s, params.penPresets, params.sharpiePresets, params.isDarkMode);
    }
  }
  for (const lbl of textLabels) {
    drawTextLabel(ctx, lbl, textPresets);
  }
  ctx.restore();

  return new Promise((resolve) => canvas.toBlob((b) => resolve(b), 'image/png'));
}

/**
 * Renders a board thumbnail PNG data URL for Welcome screen cards & list rows.
 */
export async function renderBoardThumbnailDataUrl(params: {
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
  width?: number;
  height?: number;
}): Promise<string | null> {
  const w = params.width ?? 400;
  const h = params.height ?? 300;
  const shapes = params.shapes ?? [];
  const textLabels = params.textLabels ?? [];
  const bounds = boundingBox(params.strokes, params.placedImages, params.fills, 16, shapes, textLabels);
  if (!bounds) return null;

  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;

  ctx.fillStyle = canvasBackgroundFill(params.isDarkMode, params.isWarmPaper);
  ctx.fillRect(0, 0, w, h);

  const sc = Math.min(w / bounds.width, h / bounds.height) * 0.88;
  const ox = (w - bounds.width * sc) / 2 - bounds.x * sc;
  const oy = (h - bounds.height * sc) / 2 - bounds.y * sc;

  ctx.save();
  ctx.translate(ox, oy);
  ctx.scale(sc, sc);

  for (const img of params.placedImages) {
    try {
      const el = await loadHtmlImage(imageBase64ToDataUrl(img.imageDataBase64));
      drawPlacedImage(ctx, img, el);
    } catch {
      // ignore
    }
  }
  for (const f of params.fills) {
    drawFillShape(ctx, f, params.fillPresets);
  }
  const shapePresets = params.shapePresets ?? params.penPresets;
  const textPresets = params.textPresets ?? params.penPresets;
  for (const sh of shapes) {
    drawCanvasShape(ctx, sh, shapePresets);
  }
  for (const s of params.strokes) {
    if (!s.isEraser) {
      drawStroke(ctx, s, params.penPresets, params.sharpiePresets, params.isDarkMode);
    }
  }
  for (const lbl of textLabels) {
    drawTextLabel(ctx, lbl, textPresets);
  }
  ctx.restore();

  return canvas.toDataURL('image/png');
}

/**
 * Renders a mini preview thumbnail for a CanvasScene bookmark.
 */
export async function renderSceneThumbnailDataUrl(params: {
  scene: CanvasScene;
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
  width?: number;
  height?: number;
}): Promise<string | null> {
  const w = params.width ?? 144;
  const h = params.height ?? 108;
  const shapes = params.shapes ?? [];
  const textLabels = params.textLabels ?? [];
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;

  ctx.fillStyle = params.isDarkMode
    ? 'rgb(20, 20, 23)'
    : params.isWarmPaper
    ? 'rgb(250, 245, 235)'
    : '#ffffff';
  ctx.fillRect(0, 0, w, h);

  const clampedScale = Math.min(Math.max(params.scene.scale, 0.3), 5.0);
  const refScale = (w / 1000.0) * clampedScale;
  ctx.save();
  ctx.translate(
    w / 2 - params.scene.centerX * refScale,
    h / 2 - params.scene.centerY * refScale
  );
  ctx.scale(refScale, refScale);

  for (const img of params.placedImages) {
    try {
      const el = await loadHtmlImage(imageBase64ToDataUrl(img.imageDataBase64));
      drawPlacedImage(ctx, img, el);
    } catch {
      // ignore
    }
  }
  for (const f of params.fills) {
    drawFillShape(ctx, f, params.fillPresets);
  }
  const shapePresets = params.shapePresets ?? params.penPresets;
  const textPresets = params.textPresets ?? params.penPresets;
  for (const sh of shapes) {
    drawCanvasShape(ctx, sh, shapePresets);
  }
  for (const s of params.strokes) {
    if (!s.isEraser) {
      drawStroke(ctx, s, params.penPresets, params.sharpiePresets, params.isDarkMode);
    }
  }
  for (const lbl of textLabels) {
    drawTextLabel(ctx, lbl, textPresets);
  }
  ctx.restore();

  return canvas.toDataURL('image/png');
}
