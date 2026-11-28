import React, { useEffect, useRef, useState } from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import {
  drawBackgroundGrid,
  drawCanvasShape,
  drawFillShape,
  drawPlacedImage,
  drawStroke,
  drawTextLabel,
  loadHtmlImage,
} from '../engine/renderer';
import { imageBase64ToDataUrl } from '../engine/wbCodec';
import {
  boundingBox,
  distanceSquared,
  imageRotatedBoundingBox,
  imageRotatedCorners,
  isLineLikeShape,
  rectsIntersect,
  shapeRotatedBoundingBox,
  shapeRotatedCorners,
  textLabelRotatedBoundingBox,
  textLabelRotatedCorners,
} from '../engine/geometry';
import { colorToCss, type Point } from '../types/model';
import { toggleMarkdownWrap } from '../engine/markdown';

interface CanvasStageProps {
  onBeginDraw?: () => void;
}

function resizeCssCursor(corner: number, rotation: number): string {
  const baseAngles = [(-3 * Math.PI) / 4, -Math.PI / 4, Math.PI / 4, (3 * Math.PI) / 4];
  let a = ((baseAngles[corner] ?? 0) + rotation) % Math.PI;
  if (a < 0) a += Math.PI;
  if (a < Math.PI / 8 || a >= (7 * Math.PI) / 8) return 'ew-resize';
  if (a < (3 * Math.PI) / 8) return 'nwse-resize';
  if (a < (5 * Math.PI) / 8) return 'ns-resize';
  return 'nesw-resize';
}

function drawSmoothPolygon(
  ctx: CanvasRenderingContext2D,
  pts: Point[],
  close: boolean
): void {
  if (pts.length === 0) return;
  ctx.beginPath();
  ctx.moveTo(pts[0].x, pts[0].y);
  let prev = pts[0];
  for (let i = 1; i < pts.length; i++) {
    const pt = pts[i];
    ctx.quadraticCurveTo(prev.x, prev.y, (prev.x + pt.x) / 2, (prev.y + pt.y) / 2);
    prev = pt;
  }
  if (close) ctx.closePath();
}

export const CanvasStage: React.FC<CanvasStageProps> = ({ onBeginDraw }) => {
  const state = useDrawingState();
  const containerRef = useRef<HTMLDivElement>(null);
  const bgCanvasRef = useRef<HTMLCanvasElement>(null);
  const committedCanvasRef = useRef<HTMLCanvasElement>(null);
  const liveCanvasRef = useRef<HTMLCanvasElement>(null);
  const inlineTextRef = useRef<HTMLTextAreaElement>(null);
  const imageCacheRef = useRef<Map<string, HTMLImageElement>>(new Map());

  const [viewport, setViewport] = useState({ offsetX: 0, offsetY: 0, scale: 1 });
  const viewportRef = useRef(viewport);
  viewportRef.current = viewport;

  const [canvasSize, setCanvasSize] = useState({ width: 1024, height: 768 });
  const [hasMeasuredSize, setHasMeasuredSize] = useState(false);
  const canvasSizeRef = useRef(canvasSize);
  canvasSizeRef.current = canvasSize;

  const [hoverPos, setHoverPos] = useState<Point | null>(null);
  const [cursorStyle, setCursorStyle] = useState<string>('default');
  const [hideHoverDot, setHideHoverDot] = useState(false);

  const activePointerId = useRef<number | null>(null);
  const isPanning = useRef(false);
  const spaceHeld = useRef(false);
  const lastPanPos = useRef<Point>({ x: 0, y: 0 });
  const touchPoints = useRef<Map<number, Point>>(new Map());
  const lastPinchDist = useRef<number | null>(null);
  const lastPinchCenter = useRef<Point | null>(null);
  const shapeHoldTimer = useRef<number | null>(null);
  const shapeHoldAnchor = useRef<Point>({ x: 0, y: 0 });
  const lastSelectTapRef = useRef(0);
  const lastEmptyTapRef = useRef(0);
  const animRafRef = useRef<number | null>(null);
  const dashPhaseRef = useRef(0);

  // Track canvas container size
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const update = () => {
      if (el.clientWidth > 0 && el.clientHeight > 0) {
        const nextSize = { width: el.clientWidth, height: el.clientHeight };
        canvasSizeRef.current = nextSize;
        setCanvasSize(nextSize);
        setHasMeasuredSize(true);
      }
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Spacebar panning support
  useEffect(() => {
    const onDown = (e: KeyboardEvent) => {
      if (e.code === 'Space' && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) {
        spaceHeld.current = true;
        setCursorStyle('grab');
      }
    };
    const onUp = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        spaceHeld.current = false;
        if (!isPanning.current) setCursorStyle('default');
      }
    };
    window.addEventListener('keydown', onDown);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onDown);
      window.removeEventListener('keyup', onUp);
    };
  }, []);

  // Report viewport center & scale to store
  useEffect(() => {
    if (!hasMeasuredSize) return;
    const safeScale = Math.max(viewport.scale, 0.01);
    const center = {
      x: (canvasSize.width / 2 - viewport.offsetX) / safeScale,
      y: (canvasSize.height / 2 - viewport.offsetY) / safeScale,
    };
    drawingStore.reportViewport(center, safeScale);
  }, [viewport, canvasSize, hasMeasuredSize]);

  // Smooth animate viewport to target center & scale
  const animateTo = (targetCenter: Point, targetScale: number) => {
    if (animRafRef.current !== null) cancelAnimationFrame(animRafRef.current);
    const clampedScale = Math.min(Math.max(targetScale, 0.15), 8);
    const start = { ...viewportRef.current };
    const sz = canvasSizeRef.current;
    const targetOffsetX = sz.width / 2 - targetCenter.x * clampedScale;
    const targetOffsetY = sz.height / 2 - targetCenter.y * clampedScale;
    const t0 = performance.now();
    const duration = 340;

    const step = (now: number) => {
      const p = Math.min(1, (now - t0) / duration);
      const ease = 1 - Math.pow(1 - p, 3);
      setViewport({
        offsetX: start.offsetX + (targetOffsetX - start.offsetX) * ease,
        offsetY: start.offsetY + (targetOffsetY - start.offsetY) * ease,
        scale: start.scale + (clampedScale - start.scale) * ease,
      });
      if (p < 1) {
        animRafRef.current = requestAnimationFrame(step);
      } else {
        animRafRef.current = null;
      }
    };
    animRafRef.current = requestAnimationFrame(step);
  };

  // Respond to store navigation flags (Scene jump, Recenter, Fit All, Reset Zoom)
  useEffect(() => {
    if (state.pendingSceneNavigation) {
      const sc = state.pendingSceneNavigation;
      drawingStore.consumePendingSceneNavigation();
      animateTo({ x: sc.centerX, y: sc.centerY }, sc.scale);
    }
  }, [state.pendingSceneNavigation]);

  // Auto-focus inline text editor whenever it opens
  useEffect(() => {
    if (state.isEditingText && inlineTextRef.current) {
      const el = inlineTextRef.current;
      el.focus();
      const len = el.value.length;
      el.setSelectionRange(len, len);
    }
  }, [state.isEditingText, state.editingTextId]);

  useEffect(() => {
    if (!hasMeasuredSize || !state.needsRecenter) return;
    drawingStore.consumeRecenter();
    const box = boundingBox(state.strokes, state.placedImages, state.fills, 60, state.shapes, state.textLabels);
    if (box) {
      animateTo({ x: box.x + box.width / 2, y: box.y + box.height / 2 }, 1);
    } else if (state.scenes.length > 0) {
      animateTo({ x: state.scenes[0].centerX, y: state.scenes[0].centerY }, state.scenes[0].scale);
    } else {
      animateTo({ x: 0, y: 0 }, 1);
    }
  }, [state.needsRecenter, hasMeasuredSize]);

  useEffect(() => {
    if (!hasMeasuredSize || !state.needsFitToContent) return;
    drawingStore.consumeFitToContent();
    const box = boundingBox(state.strokes, state.placedImages, state.fills, 60, state.shapes, state.textLabels);
    if (box) {
      const sz = canvasSizeRef.current;
      const fitScale = Math.min(sz.width / box.width, sz.height / box.height, 2);
      animateTo({ x: box.x + box.width / 2, y: box.y + box.height / 2 }, Math.max(fitScale, 0.2));
    } else if (state.scenes.length > 0) {
      animateTo({ x: state.scenes[0].centerX, y: state.scenes[0].centerY }, state.scenes[0].scale);
    } else {
      animateTo({ x: 0, y: 0 }, 1);
    }
  }, [state.needsFitToContent, hasMeasuredSize]);

  useEffect(() => {
    if (state.needsResetZoom) {
      drawingStore.consumeResetZoom();
      animateTo(state.currentViewportCenter, 1);
    }
  }, [state.needsResetZoom]);

  // Layer 1: Background Grid
  useEffect(() => {
    const canvas = bgCanvasRef.current;
    if (!canvas) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(canvasSize.width * dpr));
    canvas.height = Math.max(1, Math.round(canvasSize.height * dpr));
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawBackgroundGrid(
      ctx,
      canvasSize.width,
      canvasSize.height,
      state.appSettings.canvasBackground,
      state.appSettings.isDarkMode,
      state.appSettings.isWarmPaper,
      viewport.offsetX,
      viewport.offsetY,
      viewport.scale
    );
  }, [
    canvasSize,
    viewport,
    state.appSettings.canvasBackground,
    state.appSettings.isDarkMode,
    state.appSettings.isWarmPaper,
  ]);

  // Layer 2: Committed Strokes, Fills & Placed Images
  useEffect(() => {
    const canvas = committedCanvasRef.current;
    if (!canvas) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(canvasSize.width * dpr));
    canvas.height = Math.max(1, Math.round(canvasSize.height * dpr));
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, canvasSize.width, canvasSize.height);

    const safeScale = Math.max(viewport.scale, 0.01);
    const pad = 60 / safeScale;
    const visibleRect = {
      x: -viewport.offsetX / safeScale - pad,
      y: -viewport.offsetY / safeScale - pad,
      width: canvasSize.width / safeScale + pad * 2,
      height: canvasSize.height / safeScale + pad * 2,
    };

    ctx.save();
    ctx.translate(viewport.offsetX, viewport.offsetY);
    ctx.scale(safeScale, safeScale);

    const penPresets = drawingStore.penPresets;
    const sharpiePresets = drawingStore.sharpiePresets;
    const fillPresets = drawingStore.fillPresets;
    const shapePresets = drawingStore.shapePresets;
    const textPresets = drawingStore.textPresets;

    for (const img of state.placedImages) {
      if (!rectsIntersect(imageRotatedBoundingBox(img), visibleRect)) continue;
      const cached = imageCacheRef.current.get(img.id);
      if (cached) {
        drawPlacedImage(ctx, img, cached);
      } else {
        loadHtmlImage(imageBase64ToDataUrl(img.imageDataBase64))
          .then((el) => {
            imageCacheRef.current.set(img.id, el);
            setViewport((v) => ({ ...v }));
          })
          .catch(() => {});
      }
    }

    for (const fill of state.fills) {
      drawFillShape(ctx, fill, fillPresets);
    }

    for (const sh of state.shapes) {
      if (!rectsIntersect(shapeRotatedBoundingBox(sh), visibleRect)) continue;
      drawCanvasShape(ctx, sh, shapePresets);
    }

    drawingStore.spatialGrid.sync(state.strokes);
    const visibleIndices = drawingStore.spatialGrid.queryIndices(visibleRect);
    for (const idx of visibleIndices) {
      const s = state.strokes[idx];
      if (!s.isEraser) {
        drawStroke(ctx, s, penPresets, sharpiePresets, state.appSettings.isDarkMode);
      }
    }

    for (const lbl of state.textLabels) {
      if (state.isEditingText && state.editingTextId === lbl.id) continue;
      if (!rectsIntersect(textLabelRotatedBoundingBox(lbl), visibleRect)) continue;
      drawTextLabel(ctx, lbl, textPresets);
    }
    ctx.restore();
  }, [
    canvasSize,
    viewport,
    state.committedRevision,
    state.strokes,
    state.fills,
    state.placedImages,
    state.shapes,
    state.textLabels,
    state.isEditingText,
    state.editingTextId,
    state.appSettings.isDarkMode,
  ]);

  // Layer 3: Live Stroke + Active Shape + Selection Lasso / Boundary / Handles / Rotation Handle & Badge
  const hasSelectionOverlay =
    state.selectionLasso.length > 0 ||
    state.selectionBoundary.length > 0 ||
    state.selectedImageIds.length > 0 ||
    state.selectedStrokeIds.length > 0 ||
    state.selectedFillIds.length > 0 ||
    state.selectedShapeIds.length > 0 ||
    state.selectedTextIds.length > 0;

  useEffect(() => {
    let rafId: number | null = null;

    const renderLive = () => {
      const canvas = liveCanvasRef.current;
      if (!canvas) return;
      const dpr = window.devicePixelRatio || 1;
      const w = Math.max(1, Math.round(canvasSize.width * dpr));
      const h = Math.max(1, Math.round(canvasSize.height * dpr));
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, canvasSize.width, canvasSize.height);

      const safeScale = Math.max(viewport.scale, 0.01);
      const toScreen = (p: Point): Point => ({
        x: p.x * safeScale + viewport.offsetX,
        y: p.y * safeScale + viewport.offsetY,
      });

      // Active drawing / erasing stroke
      if (state.currentStroke) {
        ctx.save();
        ctx.translate(viewport.offsetX, viewport.offsetY);
        ctx.scale(safeScale, safeScale);
        drawStroke(
          ctx,
          state.currentStroke,
          drawingStore.penPresets,
          drawingStore.sharpiePresets,
          state.appSettings.isDarkMode,
          state.eraserSettings.size / safeScale
        );
        ctx.restore();
      }

      // Active shape preview
      if (state.currentShape) {
        ctx.save();
        ctx.translate(viewport.offsetX, viewport.offsetY);
        ctx.scale(safeScale, safeScale);
        drawCanvasShape(ctx, state.currentShape, drawingStore.shapePresets);
        ctx.restore();
      }

      const phase = dashPhaseRef.current;

      // Active lasso drawing
      if (state.selectionLasso.length > 1) {
        ctx.save();
        ctx.strokeStyle = 'rgba(0, 122, 255, 0.65)';
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.setLineDash([8, 5]);
        ctx.lineDashOffset = -phase;
        drawSmoothPolygon(ctx, state.selectionLasso.map(toScreen), false);
        ctx.stroke();
        ctx.restore();
      }

      // Committed selection boundary
      if (state.selectionBoundary.length >= 3) {
        ctx.save();
        ctx.strokeStyle = '#007aff';
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.setLineDash([8, 5]);
        ctx.lineDashOffset = -phase;
        drawSmoothPolygon(ctx, state.selectionBoundary.map(toScreen), true);
        ctx.stroke();
        ctx.restore();
      }

      // Selected PlacedImage rotated bounding borders & corner handles
      if (state.selectedImageIds.length > 0) {
        const selI = new Set(state.selectedImageIds);
        for (const img of state.placedImages) {
          if (!selI.has(img.id)) continue;
          const corners = imageRotatedCorners(img).map(toScreen);
          ctx.save();
          ctx.strokeStyle = '#007aff';
          ctx.lineWidth = 2;
          ctx.setLineDash([8, 5]);
          ctx.lineDashOffset = -phase;
          ctx.beginPath();
          ctx.moveTo(corners[0].x, corners[0].y);
          ctx.lineTo(corners[1].x, corners[1].y);
          ctx.lineTo(corners[2].x, corners[2].y);
          ctx.lineTo(corners[3].x, corners[3].y);
          ctx.closePath();
          ctx.stroke();

          ctx.setLineDash([]);
          for (const c of corners) {
            ctx.beginPath();
            ctx.arc(c.x, c.y, 4.8, 0, Math.PI * 2);
            ctx.fillStyle = '#007aff';
            ctx.fill();
            ctx.strokeStyle = '#ffffff';
            ctx.lineWidth = 1.6;
            ctx.stroke();
          }
          ctx.restore();
        }
      }

      // Selected CanvasShape borders & corner/endpoint handles
      if (state.selectedShapeIds.length > 0) {
        const selSh = new Set(state.selectedShapeIds);
        for (const sh of state.shapes) {
          if (!selSh.has(sh.id)) continue;
          const handles = shapeRotatedCorners(sh).map(toScreen);
          ctx.save();
          if (!isLineLikeShape(sh.kind) && handles.length === 4) {
            ctx.strokeStyle = '#007aff';
            ctx.lineWidth = 2;
            ctx.setLineDash([8, 5]);
            ctx.lineDashOffset = -phase;
            ctx.beginPath();
            ctx.moveTo(handles[0].x, handles[0].y);
            ctx.lineTo(handles[1].x, handles[1].y);
            ctx.lineTo(handles[2].x, handles[2].y);
            ctx.lineTo(handles[3].x, handles[3].y);
            ctx.closePath();
            ctx.stroke();
          }
          ctx.setLineDash([]);
          for (const pt of handles) {
            ctx.beginPath();
            ctx.arc(pt.x, pt.y, 4.8, 0, Math.PI * 2);
            ctx.fillStyle = '#007aff';
            ctx.fill();
            ctx.strokeStyle = '#ffffff';
            ctx.lineWidth = 1.6;
            ctx.stroke();
          }
          ctx.restore();
        }
      }

      // Selected TextLabel dashed borders
      if (state.selectedTextIds.length > 0) {
        const selT = new Set(state.selectedTextIds);
        for (const lbl of state.textLabels) {
          if (!selT.has(lbl.id)) continue;
          if (state.isEditingText && state.editingTextId === lbl.id) continue;
          const corners = textLabelRotatedCorners(lbl).map(toScreen);
          ctx.save();
          ctx.strokeStyle = '#007aff';
          ctx.lineWidth = 2;
          ctx.setLineDash([8, 5]);
          ctx.lineDashOffset = -phase;
          ctx.beginPath();
          ctx.moveTo(corners[0].x, corners[0].y);
          ctx.lineTo(corners[1].x, corners[1].y);
          ctx.lineTo(corners[2].x, corners[2].y);
          ctx.lineTo(corners[3].x, corners[3].y);
          ctx.closePath();
          ctx.stroke();
          ctx.restore();
        }
      }

      // Rotation handle + live angle readout pill
      if (state.currentTool === 'select') {
        const geom = drawingStore.rotationHandleGeometry(safeScale);
        if (geom) {
          const stemStart = toScreen(geom.stemStart);
          const handleCenter = toScreen(geom.handleCenter);
          const accent = state.isRotating && state.isRotationSnapped ? '#ff9500' : '#007aff';

          ctx.save();
          // Stem
          ctx.strokeStyle = accent;
          ctx.lineWidth = 1.6;
          ctx.lineCap = 'round';
          ctx.beginPath();
          ctx.moveTo(stemStart.x, stemStart.y);
          ctx.lineTo(handleCenter.x, handleCenter.y);
          ctx.stroke();

          // Knob
          const radius = state.isRotating ? 10 : 9;
          ctx.beginPath();
          ctx.arc(handleCenter.x, handleCenter.y, radius, 0, Math.PI * 2);
          ctx.fillStyle = state.isRotating
            ? accent
            : state.appSettings.isDarkMode
            ? '#242426'
            : '#ffffff';
          ctx.fill();
          ctx.strokeStyle = accent;
          ctx.lineWidth = 1.8;
          ctx.stroke();

          // Rotation arc glyph inside knob
          const glyphColor = state.isRotating ? '#ffffff' : accent;
          ctx.strokeStyle = glyphColor;
          ctx.lineWidth = 1.45;
          const arcR = radius * 0.48;
          ctx.beginPath();
          ctx.arc(handleCenter.x, handleCenter.y, arcR, -Math.PI * 0.75, Math.PI * 0.55, false);
          ctx.stroke();
          const tipAngle = Math.PI * 0.55;
          const tx = handleCenter.x + Math.cos(tipAngle) * arcR;
          const ty = handleCenter.y + Math.sin(tipAngle) * arcR;
          ctx.beginPath();
          ctx.moveTo(tx + 3, ty - 1.8);
          ctx.lineTo(tx, ty);
          ctx.lineTo(tx + 1.2, ty + 3);
          ctx.stroke();

          // Live angle badge while rotating
          if (state.isRotating) {
            const dx = handleCenter.x - stemStart.x;
            const dy = handleCenter.y - stemStart.y;
            const len = Math.max(Math.hypot(dx, dy), 0.001);
            const bx = handleCenter.x + (dx / len) * 26;
            const by = handleCenter.y + (dy / len) * 26;
            const label = drawingStore.activeRotationLabel;
            ctx.font = '600 11px -apple-system, BlinkMacSystemFont, "SF Pro Rounded", sans-serif';
            const metrics = ctx.measureText(label);
            const pillW = metrics.width + 14;
            const pillH = 20;
            ctx.fillStyle = state.isRotationSnapped ? '#ff9500' : 'rgba(0, 0, 0, 0.78)';
            ctx.beginPath();
            ctx.roundRect(bx - pillW / 2, by - pillH / 2, pillW, pillH, pillH / 2);
            ctx.fill();
            ctx.fillStyle = '#ffffff';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(label, bx, by + 0.5);
          }
          ctx.restore();
        }
      }

      if (hasSelectionOverlay) {
        dashPhaseRef.current = (dashPhaseRef.current + 0.45) % 26;
        rafId = requestAnimationFrame(renderLive);
      }
    };

    renderLive();
    return () => {
      if (rafId !== null) cancelAnimationFrame(rafId);
    };
  }, [
    canvasSize,
    viewport,
    state.currentStroke,
    state.currentShape,
    state.selectionLasso,
    state.selectionBoundary,
    state.selectedStrokeIds,
    state.selectedFillIds,
    state.selectedImageIds,
    state.selectedShapeIds,
    state.selectedTextIds,
    state.placedImages,
    state.shapes,
    state.textLabels,
    state.isEditingText,
    state.editingTextId,
    state.currentTool,
    state.isRotating,
    state.selectionRotationAngle,
    state.isRotationSnapped,
    state.appSettings.isDarkMode,
    state.eraserSettings.size,
    hasSelectionOverlay,
  ]);

  // Wheel pan & pinch-zoom
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const rect = el.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;
      if (e.ctrlKey || e.metaKey) {
        const factor = Math.exp(-e.deltaY * 0.008);
        setViewport((v) => {
          const nextScale = Math.min(Math.max(v.scale * factor, 0.15), 8);
          const ratio = nextScale / v.scale;
          return {
            offsetX: mx - (mx - v.offsetX) * ratio,
            offsetY: my - (my - v.offsetY) * ratio,
            scale: nextScale,
          };
        });
      } else {
        setViewport((v) => ({
          ...v,
          offsetX: v.offsetX - e.deltaX,
          offsetY: v.offsetY - e.deltaY,
        }));
      }
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  const toCanvas = (clientX: number, clientY: number): Point => {
    const rect = containerRef.current!.getBoundingClientRect();
    const sx = clientX - rect.left;
    const sy = clientY - rect.top;
    const v = viewportRef.current;
    const safeScale = Math.max(v.scale, 0.01);
    return { x: (sx - v.offsetX) / safeScale, y: (sy - v.offsetY) / safeScale };
  };

  const clearShapeHold = () => {
    if (shapeHoldTimer.current !== null) {
      window.clearTimeout(shapeHoldTimer.current);
      shapeHoldTimer.current = null;
    }
  };

  const scheduleShapeHold = (pt: Point) => {
    clearShapeHold();
    shapeHoldAnchor.current = pt;
    shapeHoldTimer.current = window.setTimeout(() => {
      drawingStore.snapCurrentStrokeToShape();
    }, 500);
  };

  const updateDynamicCursor = (clientX: number, clientY: number) => {
    if (isPanning.current) {
      setCursorStyle('grabbing');
      setHideHoverDot(true);
      return;
    }
    if (spaceHeld.current) {
      setCursorStyle('grab');
      setHideHoverDot(true);
      return;
    }
    if (state.currentTool === 'text') {
      setCursorStyle('text');
      setHideHoverDot(true);
      return;
    }
    if (state.currentTool === 'shape') {
      setCursorStyle('crosshair');
      setHideHoverDot(true);
      return;
    }
    if (state.currentTool !== 'select') {
      setCursorStyle('crosshair');
      setHideHoverDot(false);
      return;
    }

    const cp = toCanvas(clientX, clientY);
    const scale = Math.max(viewportRef.current.scale, 0.01);

    if (drawingStore.isResizing) {
      if (drawingStore.resizeImageId) {
        const img = state.placedImages.find((im) => im.id === drawingStore.resizeImageId);
        setCursorStyle(resizeCssCursor(drawingStore.resizeCorner, img?.rotation ?? 0));
        setHideHoverDot(true);
        return;
      }
      if (drawingStore.resizeShapeId) {
        const sh = state.shapes.find((x) => x.id === drawingStore.resizeShapeId);
        if (sh) {
          setCursorStyle(
            isLineLikeShape(sh.kind) ? 'crosshair' : resizeCssCursor(drawingStore.resizeCorner, sh.rotation ?? 0)
          );
          setHideHoverDot(true);
          return;
        }
      }
    }
    if (state.isRotating) {
      setCursorStyle('grabbing');
      setHideHoverDot(true);
      return;
    }

    const resizeHit = drawingStore.hitTestResizeHandle(cp, scale);
    if (resizeHit) {
      const img = state.placedImages.find((im) => im.id === resizeHit.imgId);
      setCursorStyle(resizeCssCursor(resizeHit.corner, img?.rotation ?? 0));
      setHideHoverDot(true);
      return;
    }

    const shapeHit = drawingStore.hitTestShapeHandle(cp, scale);
    if (shapeHit) {
      const sh = state.shapes.find((x) => x.id === shapeHit.shapeId);
      if (sh) {
        setCursorStyle(
          isLineLikeShape(sh.kind) ? 'crosshair' : resizeCssCursor(shapeHit.handleIndex, sh.rotation ?? 0)
        );
        setHideHoverDot(true);
        return;
      }
    }

    if (drawingStore.hitTestRotateHandle(cp, scale)) {
      setCursorStyle('grab');
      setHideHoverDot(true);
      return;
    }

    if (
      drawingStore.hasSelection &&
      (drawingStore.isPointOnSelectedItem(cp) ||
        (state.selectionBoundary.length > 0 && drawingStore.isPointInSelectionBoundary(cp)))
    ) {
      setCursorStyle('move');
      setHideHoverDot(false);
      return;
    }

    setCursorStyle('default');
    setHideHoverDot(false);
  };

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = containerRef.current;
    if (!el) return;
    el.setPointerCapture(e.pointerId);

    if (e.pointerType === 'touch') {
      touchPoints.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (touchPoints.current.size === 2) {
        clearShapeHold();
        const pts = Array.from(touchPoints.current.values());
        lastPinchDist.current = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
        lastPinchCenter.current = { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
        return;
      }
    }

    const isMiddleClick = e.button === 1;
    const isFingerPan =
      state.appSettings.pencilOnly && e.pointerType === 'touch' && state.currentTool !== 'select';

    if (isMiddleClick || isFingerPan || spaceHeld.current) {
      isPanning.current = true;
      activePointerId.current = e.pointerId;
      lastPanPos.current = { x: e.clientX, y: e.clientY };
      setCursorStyle('grabbing');
      setHideHoverDot(true);
      return;
    }

    if (e.button !== 0 && e.pointerType === 'mouse') return;

    if (e.pointerType === 'pen' && (e.button === 5 || (e.buttons & 32) !== 0)) {
      drawingStore.toggleEraserFromStylus();
    }

    onBeginDraw?.();
    const cp = toCanvas(e.clientX, e.clientY);
    const scale = Math.max(viewportRef.current.scale, 0.01);
    drawingStore.lastCanvasTapLocation = cp;

    if (state.isEditingText) {
      drawingStore.commitTextEditing();
      if (state.currentTool === 'text') {
        const existing = drawingStore.hitTestTextLabel(cp);
        if (existing) {
          drawingStore.beginTextEditing(existing.position, existing.id);
        }
      }
      return;
    }

    activePointerId.current = e.pointerId;

    if (state.currentTool === 'select') {
      const hasSel = drawingStore.hasSelection || state.selectionBoundary.length > 0;
      if (hasSel) {
        if (drawingStore.hitTestRotateHandle(cp, scale)) {
          drawingStore.beginRotate(cp, scale);
          updateDynamicCursor(e.clientX, e.clientY);
          return;
        }
        if (
          drawingStore.hitTestResizeHandle(cp, scale) !== null ||
          drawingStore.hitTestShapeHandle(cp, scale) !== null
        ) {
          drawingStore.beginMove(cp, scale);
          updateDynamicCursor(e.clientX, e.clientY);
          return;
        }
        const onSelected =
          drawingStore.isPointOnSelectedItem(cp) ||
          (state.selectionBoundary.length > 0 && drawingStore.isPointInSelectionBoundary(cp));
        if (onSelected) {
          const now = Date.now();
          if (now - lastSelectTapRef.current < 360) {
            lastSelectTapRef.current = 0;
            const hitLbl = drawingStore.hitTestTextLabel(cp);
            if (hitLbl && state.selectedTextIds.includes(hitLbl.id)) {
              drawingStore.beginTextEditing(hitLbl.position, hitLbl.id);
              activePointerId.current = null;
              return;
            }
            drawingStore.setQuickMenu(true, { x: e.clientX + 20, y: e.clientY - 12 });
            return;
          }
          lastSelectTapRef.current = now;
          drawingStore.beginMove(cp, scale);
          return;
        }
        drawingStore.clearSelection();
        drawingStore.pendingDeselectPoint = cp;
        return;
      }

      const now = Date.now();
      const onElement = drawingStore.hasElement(cp, scale);
      if (!onElement && now - lastEmptyTapRef.current < 360) {
        lastEmptyTapRef.current = 0;
        drawingStore.setQuickMenu(true, { x: e.clientX + 20, y: e.clientY - 12 });
        return;
      }
      lastEmptyTapRef.current = onElement ? 0 : now;
      drawingStore.beginLasso(cp);
      return;
    }

    if (state.currentTool === 'fill') {
      drawingStore.floodFill(cp);
      return;
    }

    if (state.currentTool === 'shape') {
      drawingStore.beginShape(cp);
      return;
    }

    if (state.currentTool === 'text') {
      activePointerId.current = null;
      const existing = drawingStore.hitTestTextLabel(cp);
      if (existing) {
        drawingStore.beginTextEditing(existing.position, existing.id);
      } else {
        drawingStore.beginTextEditing(cp);
      }
      return;
    }

    drawingStore.beginStroke(cp, state.currentTool === 'eraser');
    if (state.currentTool === 'pen' || state.currentTool === 'sharpie') {
      scheduleShapeHold(cp);
    }
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    const rect = containerRef.current?.getBoundingClientRect();
    if (rect) {
      setHoverPos({ x: e.clientX - rect.left, y: e.clientY - rect.top });
    }

    if (e.pointerType === 'touch' && touchPoints.current.has(e.pointerId)) {
      touchPoints.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (touchPoints.current.size === 2) {
        const pts = Array.from(touchPoints.current.values());
        const dist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
        const center = { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
        if (lastPinchDist.current && lastPinchCenter.current && rect) {
          const factor = dist / Math.max(lastPinchDist.current, 1);
          const dx = center.x - lastPinchCenter.current.x;
          const dy = center.y - lastPinchCenter.current.y;
          const mx = center.x - rect.left;
          const my = center.y - rect.top;
          setViewport((v) => {
            const nextScale = Math.min(Math.max(v.scale * factor, 0.15), 8);
            const ratio = nextScale / v.scale;
            return {
              offsetX: mx - (mx - v.offsetX) * ratio + dx,
              offsetY: my - (my - v.offsetY) * ratio + dy,
              scale: nextScale,
            };
          });
        }
        lastPinchDist.current = dist;
        lastPinchCenter.current = center;
        return;
      }
    }

    updateDynamicCursor(e.clientX, e.clientY);

    if (activePointerId.current !== e.pointerId) return;

    if (isPanning.current) {
      const dx = e.clientX - lastPanPos.current.x;
      const dy = e.clientY - lastPanPos.current.y;
      lastPanPos.current = { x: e.clientX, y: e.clientY };
      setViewport((v) => ({ ...v, offsetX: v.offsetX + dx, offsetY: v.offsetY + dy }));
      return;
    }

    const cp = toCanvas(e.clientX, e.clientY);
    const scale = Math.max(viewportRef.current.scale, 0.01);

    if (state.currentTool === 'select') {
      if (drawingStore.pendingDeselectPoint) {
        const thresh = 6 / Math.max(scale, 0.1);
        if (distanceSquared(drawingStore.pendingDeselectPoint, cp) > thresh * thresh) {
          const start = drawingStore.pendingDeselectPoint;
          drawingStore.pendingDeselectPoint = null;
          drawingStore.beginLasso(start);
          drawingStore.addLassoPoint(cp);
        }
        return;
      }
      if (state.isRotating) {
        drawingStore.updateRotate(cp, e.shiftKey);
        return;
      }
      if (drawingStore.isMoving || drawingStore.isResizing) {
        const delta = {
          width: cp.x - drawingStore.lastMovePoint.x,
          height: cp.y - drawingStore.lastMovePoint.y,
        };
        drawingStore.moveSelected(delta, e.shiftKey);
        drawingStore.lastMovePoint = cp;
        return;
      }
      if (state.selectionLasso.length > 0) {
        drawingStore.addLassoPoint(cp);
      }
      return;
    }

    if (state.currentTool === 'fill' || state.currentTool === 'text') return;

    if (state.currentTool === 'shape') {
      drawingStore.updateShape(cp, e.shiftKey);
      return;
    }

    const nativeEvt = e.nativeEvent;
    const coalesced =
      typeof nativeEvt.getCoalescedEvents === 'function'
        ? nativeEvt.getCoalescedEvents()
        : [nativeEvt];
    const eventsToProcess = coalesced.length > 0 ? coalesced : [nativeEvt];

    for (const ev of eventsToProcess) {
      const pt = toCanvas(ev.clientX, ev.clientY);
      if (state.currentTool === 'pen' || state.currentTool === 'sharpie') {
        if (Math.hypot(pt.x - shapeHoldAnchor.current.x, pt.y - shapeHoldAnchor.current.y) > 6 / Math.max(scale, 0.1)) {
          scheduleShapeHold(pt);
        }
      }
      drawingStore.addStrokePoint(pt);
    }
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'touch') {
      touchPoints.current.delete(e.pointerId);
      if (touchPoints.current.size < 2) {
        lastPinchDist.current = null;
        lastPinchCenter.current = null;
      }
    }
    if (activePointerId.current !== e.pointerId) return;
    activePointerId.current = null;
    clearShapeHold();

    if (isPanning.current) {
      isPanning.current = false;
      updateDynamicCursor(e.clientX, e.clientY);
      return;
    }

    const scale = Math.max(viewportRef.current.scale, 0.01);
    if (state.currentTool === 'select') {
      if (drawingStore.pendingDeselectPoint) {
        const tap = drawingStore.pendingDeselectPoint;
        drawingStore.pendingDeselectPoint = null;
        drawingStore.selectElement(tap, scale);
      } else if (state.isRotating) {
        drawingStore.commitRotate();
      } else if (drawingStore.isMoving || drawingStore.isResizing) {
        drawingStore.commitMove();
      } else if (state.selectionLasso.length > 0) {
        drawingStore.endLasso(scale);
      }
      updateDynamicCursor(e.clientX, e.clientY);
      return;
    }

    if (state.currentTool === 'shape') {
      drawingStore.endShape();
      return;
    }

    if (state.currentTool !== 'fill' && state.currentTool !== 'text') {
      drawingStore.endStroke(scale);
    }
  };

  // Drag-and-drop images onto canvas
  const handleDragOver = (e: React.DragEvent<HTMLDivElement>) => {
    if (Array.from(e.dataTransfer.types).includes('Files')) {
      e.preventDefault();
    }
  };

  const handleDrop = async (e: React.DragEvent<HTMLDivElement>) => {
    const files = Array.from(e.dataTransfer.files).filter((f) => f.type.startsWith('image/'));
    if (files.length === 0) return;
    e.preventDefault();
    const dropPt = toCanvas(e.clientX, e.clientY);
    for (let i = 0; i < files.length; i++) {
      await drawingStore.addImageFromBlob(files[i], i, dropPt);
    }
  };

  const hoverDotSize =
    state.currentTool === 'eraser'
      ? Math.max(state.eraserSettings.size, 6)
      : state.currentTool === 'fill'
      ? 10
      : state.currentTool === 'pen'
      ? Math.max(state.penSettings.thickness * 1.5, 4)
      : state.currentTool === 'sharpie'
      ? Math.max(state.sharpieSettings.thickness * 1.5, 4)
      : 4;

  const hoverDotColor =
    state.currentTool === 'eraser'
      ? 'rgba(255, 59, 48, 0.25)'
      : state.appSettings.isDarkMode
      ? 'rgba(255, 255, 255, 0.4)'
      : 'rgba(0, 0, 0, 0.4)';

  return (
    <div
      ref={containerRef}
      className="canvas-stage"
      style={{ cursor: cursorStyle }}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      onPointerLeave={() => {
        setHoverPos(null);
        setCursorStyle('default');
      }}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
    >
      <canvas ref={bgCanvasRef} className="canvas-layer" />
      <canvas ref={committedCanvasRef} className="canvas-layer" />
      <canvas ref={liveCanvasRef} className="canvas-layer" />
      {state.isEditingText && (() => {
        const safeScale = Math.max(viewport.scale, 0.1);
        const scaledFont = Math.max(10, state.editingTextFontSize * safeScale);
        const lines = state.editingTextDraft.split('\n');
        const longest = lines.reduce((m, l) => Math.max(m, l.length), 0);
        const minW = Math.max(120 * safeScale, scaledFont * 6.8, (longest + 2) * scaledFont * 0.65 + 24);
        const minH = Math.max(scaledFont * 1.4, lines.length * scaledFont * 1.28 + 10);
        const left = state.editingTextPosition.x * safeScale + viewport.offsetX;
        const top = state.editingTextPosition.y * safeScale + viewport.offsetY;
        return (
          <textarea
            ref={inlineTextRef}
            className="inline-text-editor"
            value={state.editingTextDraft}
            placeholder="Type text…"
            spellCheck={false}
            style={{
              left,
              top,
              width: minW,
              height: minH,
              fontSize: scaledFont,
              lineHeight: 1.28,
              fontWeight: state.editingTextIsBold ? 700 : 400,
              color: colorToCss(drawingStore.editingTextDisplayColor),
              transform: state.editingTextRotation
                ? `rotate(${state.editingTextRotation}rad)`
                : undefined,
            }}
            onPointerDown={(e) => e.stopPropagation()}
            onChange={(e) => drawingStore.setEditingTextDraft(e.target.value)}
            onKeyDown={(e) => {
              e.stopPropagation();
              const mod = e.metaKey || e.ctrlKey;
              if (mod && !e.altKey) {
                const k = e.key.toLowerCase();
                let markers: [string, string] | null = null;
                if (k === 'b' && !e.shiftKey) markers = ['**', '**'];
                else if (k === 'i' && !e.shiftKey) markers = ['*', '*'];
                else if (k === 'u' && !e.shiftKey) markers = ['<u>', '</u>'];
                else if (k === 'x' && e.shiftKey) markers = ['~~', '~~'];
                else if ((k === 'e' || k === '`') && !e.shiftKey) markers = ['`', '`'];
                if (markers) {
                  e.preventDefault();
                  const el = e.currentTarget;
                  const res = toggleMarkdownWrap(
                    el.value,
                    el.selectionStart ?? el.value.length,
                    el.selectionEnd ?? el.value.length,
                    markers[0],
                    markers[1]
                  );
                  drawingStore.setEditingTextDraft(res.text);
                  requestAnimationFrame(() => {
                    if (inlineTextRef.current) {
                      inlineTextRef.current.setSelectionRange(res.selectionStart, res.selectionEnd);
                    }
                  });
                  return;
                }
              }
              if (e.key === 'Escape') {
                e.preventDefault();
                drawingStore.cancelTextEditing();
              } else if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                drawingStore.commitTextEditing();
              }
            }}
          />
        );
      })()}
      {hoverPos && !hideHoverDot && !state.isEditingText && (
        <div
          className="hover-dot"
          style={{
            width: hoverDotSize,
            height: hoverDotSize,
            backgroundColor: hoverDotColor,
            transform: `translate(${hoverPos.x - hoverDotSize / 2}px, ${hoverPos.y - hoverDotSize / 2}px)`,
          }}
        />
      )}
    </div>
  );
};
