import type { FillShape, PlacedImage, Point, Stroke } from '../types/model';

export interface CanvasSnapshot {
  strokes: Stroke[];
  placedImages: PlacedImage[];
  fills: FillShape[];
  selectedStrokeIds: string[];
  selectedImageIds: string[];
  selectedFillIds: string[];
  selectionBoundary: Point[];
}

export class CanvasHistory {
  readonly maxSnapshots: number;
  private undoStack: CanvasSnapshot[] = [];
  private redoStack: CanvasSnapshot[] = [];

  constructor(maxSnapshots = 100) {
    this.maxSnapshots = Math.max(1, maxSnapshots);
  }

  get canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  get canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  get undoCount(): number {
    return this.undoStack.length;
  }

  get redoCount(): number {
    return this.redoStack.length;
  }

  record(snapshot: CanvasSnapshot): void {
    this.undoStack.push(cloneSnapshot(snapshot));
    if (this.undoStack.length > this.maxSnapshots) {
      this.undoStack.splice(0, this.undoStack.length - this.maxSnapshots);
    }
    this.redoStack = [];
  }

  undo(current: CanvasSnapshot): CanvasSnapshot | null {
    const prev = this.undoStack.pop();
    if (!prev) return null;
    this.redoStack.push(cloneSnapshot(current));
    if (this.redoStack.length > this.maxSnapshots) {
      this.redoStack.splice(0, this.redoStack.length - this.maxSnapshots);
    }
    return cloneSnapshot(prev);
  }

  redo(current: CanvasSnapshot): CanvasSnapshot | null {
    const next = this.redoStack.pop();
    if (!next) return null;
    this.undoStack.push(cloneSnapshot(current));
    if (this.undoStack.length > this.maxSnapshots) {
      this.undoStack.splice(0, this.undoStack.length - this.maxSnapshots);
    }
    return cloneSnapshot(next);
  }

  clear(): void {
    this.undoStack = [];
    this.redoStack = [];
  }
}

function cloneSnapshot(s: CanvasSnapshot): CanvasSnapshot {
  return {
    strokes: s.strokes.map((st) => ({
      ...st,
      color: { ...st.color },
      points: st.points.map((p) => ({ x: p.x, y: p.y })),
    })),
    placedImages: s.placedImages.map((img) => ({
      ...img,
      position: { ...img.position },
      size: { ...img.size },
    })),
    fills: s.fills.map((f) => ({
      ...f,
      color: { ...f.color },
      contours: f.contours.map((loop) => loop.map((p) => ({ x: p.x, y: p.y }))),
    })),
    selectedStrokeIds: [...s.selectedStrokeIds],
    selectedImageIds: [...s.selectedImageIds],
    selectedFillIds: [...s.selectedFillIds],
    selectionBoundary: s.selectionBoundary.map((p) => ({ x: p.x, y: p.y })),
  };
}
