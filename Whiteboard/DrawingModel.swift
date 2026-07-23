import Combine
import SwiftUI

struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    let color: Color
    let lineWidth: CGFloat
    let isEraser: Bool
}

struct FillRegion: Identifiable {
    let id = UUID()
    let path: CGPath
    let color: Color
}

enum Tool {
    case pen, eraser, fill
}

typealias CanvasSnapshot = (strokes: [Stroke], fillRegions: [FillRegion])

class DrawingModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var fillRegions: [FillRegion] = []
    @Published var currentTool: Tool = .pen
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    var currentStroke: Stroke?

    private var undoStack: [CanvasSnapshot] = []
    private var redoStack: [CanvasSnapshot] = []

    private func saveState() {
        undoStack.append((strokes, fillRegions))
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    private func updateUndoRedo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func beginStroke(at point: CGPoint, isEraser: Bool) {
        currentStroke = Stroke(
            points: [point],
            color: isEraser ? .white : .black,
            lineWidth: isEraser ? 20 : 2,
            isEraser: isEraser
        )
    }

    func addPoint(_ point: CGPoint) {
        currentStroke?.points.append(point)
    }

    func endStroke() {
        guard let stroke = currentStroke else { currentStroke = nil; return }
        currentStroke = nil

        saveState()

        if stroke.isEraser {
            erase(stroke)
        } else if stroke.points.count >= 2 {
            strokes.append(stroke)
        }
        updateUndoRedo()
    }

    private func erase(_ eraser: Stroke) {
        let threshold = eraser.lineWidth / 2 + 2

        var newStrokes: [Stroke] = []
        for pen in strokes where !pen.isEraser {
            var segment: [CGPoint] = []
            for pp in pen.points {
                let isErased = eraser.points.contains { ep in
                    let dx = pp.x - ep.x, dy = pp.y - ep.y
                    return sqrt(dx * dx + dy * dy) < threshold
                }
                if isErased {
                    if segment.count >= 2 {
                        newStrokes.append(Stroke(points: segment, color: pen.color, lineWidth: pen.lineWidth, isEraser: false))
                    }
                    segment = []
                } else {
                    segment.append(pp)
                }
            }
            if segment.count >= 2 {
                newStrokes.append(Stroke(points: segment, color: pen.color, lineWidth: pen.lineWidth, isEraser: false))
            }
        }
        strokes = newStrokes

        fillRegions = fillRegions.filter { region in
            for ep in eraser.points {
                if region.path.contains(ep) { return false }
            }
            return true
        }
    }

    func performFill(at canvasPoint: CGPoint) {
        saveState()
        guard let path = FloodFill.fillPath(at: canvasPoint, strokes: strokes) else {
            updateUndoRedo()
            return
        }
        let region = FillRegion(path: path, color: Color.red.opacity(0.2))
        fillRegions.append(region)
        updateUndoRedo()
    }

    func selectTool(_ tool: Tool) {
        currentTool = tool
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append((strokes, fillRegions))
        let prev = undoStack.removeLast()
        strokes = prev.strokes
        fillRegions = prev.fillRegions
        updateUndoRedo()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append((strokes, fillRegions))
        let next = redoStack.removeLast()
        strokes = next.strokes
        fillRegions = next.fillRegions
        updateUndoRedo()
    }

    func clear() {
        saveState()
        strokes.removeAll()
        fillRegions.removeAll()
        currentStroke = nil
        updateUndoRedo()
    }
}
