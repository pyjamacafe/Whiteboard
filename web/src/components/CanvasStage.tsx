import React, { useEffect, useRef, useState } from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import {
  drawBackgroundGrid,
  drawFillShape,
  drawPlacedImage,
  drawStroke,
  loadHtmlImage,
} from '../engine/renderer';
import { imageBase64ToDataUrl } from '../engine/wbCodec';
import { imageRotatedBoundingBox, rectsIntersect } from '../engine/geometry';
import type { Point } from '../types/model';

interface CanvasStageProps {
  onBeginDraw?: () => void;
}

export const CanvasStage: React.FC<CanvasStageProps> = ({ onBeginDraw }) => {
  const state = useDrawingState();
  const containerRef = useRef<HTMLDivElement>(null);
  const bgCanvasRef = useRef<HTMLCanvasElement>(null);
  const committedCanvasRef = useRef<HTMLCanvasElement>(null);
  const liveCanvasRef = useRef<HTMLCanvasElement>(null);
  const imageCacheRef = useRef<Map<string, HTMLImageElement>>(new Map());

  const [viewport, setViewport] = useState({ offsetX: 0, offsetY: 0, scale: 1 });
  const viewportRef = useRef(viewport);
  viewportRef.current = viewport;

  const [canvasSize, setCanvasSize] = useState({ width: 1024, height: 768 });
  const [hoverPos, setHoverPos] = useState<Point | null>(null);

  const activePointerId = useRef<number | null>(null);
  const isPanning = useRef(false);
  const lastPanPos = useRef<Point>({ x: 0, y: 0 });
  const touchPoints = useRef<Map<number, Point>>(new Map());
  const lastPinchDist = useRef<number | null>(null);
  const lastPinchCenter = useRef<Point | null>(null);
  const shapeHoldTimer = useRef<number | null>(null);
  const shapeHoldAnchor = useRef<Point>({ x: 0, y: 0 });

  // Resize observer
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const update = () => {
      setCanvasSize({ width: el.clientWidth, height: el.clientHeight });
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

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

  // Layer 2: Committed Strokes, Fills & Placed Images (viewport-culled via SpatialHashGrid)
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

    // Images
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

    // Fills
    for (const fill of state.fills) {
      drawFillShape(ctx, fill, fillPresets);
    }

    // Strokes via spatial index
    drawingStore.spatialGrid.sync(state.strokes);
    const visibleIndices = drawingStore.spatialGrid.queryIndices(visibleRect);
    for (const idx of visibleIndices) {
      const s = state.strokes[idx];
      if (!s.isEraser) {
        drawStroke(ctx, s, penPresets, sharpiePresets, state.appSettings.isDarkMode);
      }
    }
    ctx.restore();
  }, [
    canvasSize,
    viewport,
    state.committedRevision,
    state.strokes,
    state.fills,
    state.placedImages,
    state.appSettings.isDarkMode,
  ]);

  // Layer 3: Live active stroke
  useEffect(() => {
    const canvas = liveCanvasRef.current;
    if (!canvas) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(canvasSize.width * dpr));
    canvas.height = Math.max(1, Math.round(canvasSize.height * dpr));
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, canvasSize.width, canvasSize.height);

    const cur = state.currentStroke;
    if (!cur) return;

    const safeScale = Math.max(viewport.scale, 0.01);
    ctx.save();
    ctx.translate(viewport.offsetX, viewport.offsetY);
    ctx.scale(safeScale, safeScale);
    drawStroke(
      ctx,
      cur,
      drawingStore.penPresets,
      drawingStore.sharpiePresets,
      state.appSettings.isDarkMode,
      state.eraserSettings.size / safeScale
    );
    ctx.restore();
  }, [canvasSize, viewport, state.currentStroke, state.appSettings.isDarkMode, state.eraserSettings.size]);

  // Wheel pan & zoom (pinch-to-zoom on trackpad sets ctrlKey)
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
          const nextOffsetX = mx - (mx - v.offsetX) * ratio;
          const nextOffsetY = my - (my - v.offsetY) * ratio;
          drawingStore.setZoomDisplayScale(nextScale);
          return { offsetX: nextOffsetX, offsetY: nextOffsetY, scale: nextScale };
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

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = containerRef.current;
    if (!el) return;
    el.setPointerCapture(e.pointerId);

    // Track multi-touch for pinch/two-finger pan
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

    // Middle-click or Spacebar-pan or Pen-Only finger pan
    const isMiddleClick = e.button === 1;
    const isFingerPan =
      state.appSettings.pencilOnly &&
      e.pointerType === 'touch' &&
      state.currentTool !== 'select';

    if (isMiddleClick || isFingerPan) {
      isPanning.current = true;
      activePointerId.current = e.pointerId;
      lastPanPos.current = { x: e.clientX, y: e.clientY };
      return;
    }

    if (e.button !== 0 && e.pointerType === 'mouse') return;

    // Stylus eraser end (button === 5 or buttons & 32)
    if (e.pointerType === 'pen' && (e.button === 5 || (e.buttons & 32) !== 0)) {
      drawingStore.toggleEraserFromStylus();
    }

    onBeginDraw?.();
    activePointerId.current = e.pointerId;
    const cp = toCanvas(e.clientX, e.clientY);

    if (state.currentTool === 'fill') {
      drawingStore.floodFill(cp);
      return;
    }

    if (state.currentTool === 'pen' || state.currentTool === 'sharpie' || state.currentTool === 'eraser') {
      drawingStore.beginStroke(cp, state.currentTool === 'eraser');
      if (state.currentTool === 'pen' || state.currentTool === 'sharpie') {
        scheduleShapeHold(cp);
      }
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
            drawingStore.setZoomDisplayScale(nextScale);
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

    if (activePointerId.current !== e.pointerId) return;

    if (isPanning.current) {
      const dx = e.clientX - lastPanPos.current.x;
      const dy = e.clientY - lastPanPos.current.y;
      lastPanPos.current = { x: e.clientX, y: e.clientY };
      setViewport((v) => ({ ...v, offsetX: v.offsetX + dx, offsetY: v.offsetY + dy }));
      return;
    }

    const nativeEvt = e.nativeEvent;
    const coalesced =
      typeof nativeEvt.getCoalescedEvents === 'function'
        ? nativeEvt.getCoalescedEvents()
        : [nativeEvt];
    const eventsToProcess = coalesced.length > 0 ? coalesced : [nativeEvt];

    for (const ev of eventsToProcess) {
      const cp = toCanvas(ev.clientX, ev.clientY);
      if (state.currentTool === 'pen' || state.currentTool === 'sharpie') {
        const moveDist = Math.hypot(cp.x - shapeHoldAnchor.current.x, cp.y - shapeHoldAnchor.current.y);
        if (moveDist > 6 / Math.max(viewportRef.current.scale, 0.1)) {
          scheduleShapeHold(cp);
        }
      }
      drawingStore.addStrokePoint(cp);
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
      return;
    }

    if (state.currentTool !== 'fill' && state.currentTool !== 'select') {
      drawingStore.endStroke(viewportRef.current.scale);
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
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      onPointerLeave={() => setHoverPos(null)}
    >
      <canvas ref={bgCanvasRef} className="canvas-layer" />
      <canvas ref={committedCanvasRef} className="canvas-layer" />
      <canvas ref={liveCanvasRef} className="canvas-layer" />
      {hoverPos && (
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
