import CoreGraphics
import Foundation

/// Full canvas state snapshot captured for undo/redo.
struct CanvasSnapshot {
    let strokes: [Stroke]
    let placedImages: [PlacedImage]
    let fills: [FillShape]
    let selectedStrokeIds: Set<UUID>
    let selectedImageIds: Set<UUID>
    let selectedFillIds: Set<UUID>
    let selectionBoundary: [CGPoint]

    init(
        strokes: [Stroke],
        placedImages: [PlacedImage],
        fills: [FillShape] = [],
        selectedStrokeIds: Set<UUID>,
        selectedImageIds: Set<UUID>,
        selectedFillIds: Set<UUID> = [],
        selectionBoundary: [CGPoint]
    ) {
        self.strokes = strokes
        self.placedImages = placedImages
        self.fills = fills
        self.selectedStrokeIds = selectedStrokeIds
        self.selectedImageIds = selectedImageIds
        self.selectedFillIds = selectedFillIds
        self.selectionBoundary = selectionBoundary
    }
}

/// Bounded undo/redo stack for canvas mutations.
struct CanvasHistory {
    let maxSnapshots: Int
    private(set) var undoStack: [CanvasSnapshot] = []
    private(set) var redoStack: [CanvasSnapshot] = []

    init(maxSnapshots: Int = 100) {
        self.maxSnapshots = max(1, maxSnapshots)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func push(_ snapshot: CanvasSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > maxSnapshots {
            undoStack.removeFirst(undoStack.count - maxSnapshots)
        }
        redoStack.removeAll()
    }

    mutating func undo(current: CanvasSnapshot) -> CanvasSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: CanvasSnapshot) -> CanvasSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        if undoStack.count > maxSnapshots {
            undoStack.removeFirst(undoStack.count - maxSnapshots)
        }
        return next
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
