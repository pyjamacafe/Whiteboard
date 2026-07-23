import Combine
import SwiftUI

struct Stroke: Identifiable {
    var id = UUID()
    var points: [CGPoint]
    let color: Color
    let lineWidth: CGFloat
    let isEraser: Bool
    let isHighlighter: Bool
}

struct FillRegion: Identifiable {
    var id = UUID()
    let path: CGPath
    let color: Color
}

enum Tool: String, CaseIterable {
    case pen, eraser, fill, select, highlighter
}

struct PenSettings {
    var color: Color = .black
    var thickness: CGFloat = 2
    var smoothness: CGFloat = 3
    var presets: [Color] = [.black, .red, .orange, .yellow, .green, .blue, .purple, .brown]
}

struct FillSettings {
    var color: Color = .red
    var opacity: Double = 0.1
    var presets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint]
}

enum EraserMode: String, CaseIterable {
    case partial = "Partial"
    case full = "Full Stroke"
}

struct EraserSettings {
    var mode: EraserMode = .partial
}

struct HighlighterSettings {
    var color: Color = .yellow
    var thickness: CGFloat = 15
    var opacity: Double = 0.3
}

typealias CanvasSnapshot = (strokes: [Stroke], fillRegions: [FillRegion], selectedStrokeIds: Set<UUID>, selectedFillIds: Set<UUID>)

class DrawingModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var fillRegions: [FillRegion] = []
    @Published var currentTool: Tool = .pen
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    var currentStroke: Stroke?
    @Published var penSettings = PenSettings()
    @Published var fillSettings = FillSettings()
    @Published var eraserSettings = EraserSettings()
    @Published var highlighterSettings = HighlighterSettings()
    @Published var selectionLasso: [CGPoint] = []
    @Published var selectionBoundary: [CGPoint] = []
    @Published var selectedStrokeIds: Set<UUID> = []
    @Published var selectedFillIds: Set<UUID> = []

    private var undoStack: [CanvasSnapshot] = []
    private var redoStack: [CanvasSnapshot] = []

    private func saveState() {
        undoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds))
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    private func updateUndoRedo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func beginStroke(at point: CGPoint, isEraser: Bool) {
        let isHighlight = currentTool == .highlighter
        currentStroke = Stroke(
            points: [point],
            color: isEraser ? .white : isHighlight ? highlighterSettings.color.opacity(highlighterSettings.opacity) : penSettings.color,
            lineWidth: isEraser ? 20 : isHighlight ? highlighterSettings.thickness : penSettings.thickness,
            isEraser: isEraser,
            isHighlighter: isHighlight
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
            var finalStroke = stroke
            if penSettings.smoothness > 1 && !stroke.isEraser && stroke.lineWidth < 10 {
                let simplified = simplify(stroke.points, epsilon: penSettings.smoothness)
                if simplified.count >= 2 {
                    finalStroke = Stroke(id: stroke.id, points: simplified, color: stroke.color, lineWidth: stroke.lineWidth, isEraser: false, isHighlighter: stroke.isHighlighter)
                }
            }
            strokes.append(finalStroke)
        }
        updateUndoRedo()
    }

    // MARK: - Lasso Selection

    func beginLasso(at point: CGPoint) {
        selectionLasso = [point]
    }

    func addLassoPoint(_ point: CGPoint) {
        selectionLasso.append(point)
    }

    func endLasso() {
        guard selectionLasso.count >= 3 else { selectionLasso = []; return }

        saveState()

        let path = CGMutablePath()
        path.move(to: selectionLasso[0])
        for i in 1..<selectionLasso.count {
            path.addLine(to: selectionLasso[i])
        }
        path.closeSubpath()

        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()

        for stroke in strokes where !stroke.isEraser {
            for p in stroke.points {
                if path.contains(p) {
                    selectedStrokeIds.insert(stroke.id)
                    break
                }
            }
        }

        for region in fillRegions {
            let box = region.path.boundingBox
            let center = CGPoint(x: box.midX, y: box.midY)
            if path.contains(center) || path.contains(box.origin) {
                selectedFillIds.insert(region.id)
            }
        }

        selectionBoundary = selectionLasso
        selectionLasso = []
        updateUndoRedo()
    }

    // MARK: - Move Selection

    var isMoving: Bool = false
    var lastMovePoint: CGPoint = .zero
    private var moveDidChange: Bool = false

    func isPointOnSelectedItem(_ point: CGPoint) -> Bool {
        let threshold: CGFloat = 15
        for s in strokes where selectedStrokeIds.contains(s.id) {
            for i in 0..<s.points.count - 1 {
                let d = pointSegDist(point, s.points[i], s.points[i + 1])
                if d < threshold { return true }
            }
        }
        for r in fillRegions where selectedFillIds.contains(r.id) {
            if r.path.contains(point) { return true }
        }
        return false
    }

    func beginMove(at point: CGPoint) {
        guard isPointOnSelectedItem(point) else {
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectionBoundary.removeAll()
            beginLasso(at: point)
            return
        }
        isMoving = true
        lastMovePoint = point
        moveDidChange = false
    }

    func commitMove() {
        guard isMoving else { return }
        isMoving = false
        if moveDidChange {
            saveState()
            updateUndoRedo()
        }
    }

    func moveSelected(by offset: CGSize) {
        guard isMoving, offset != .zero else { return }
        moveDidChange = true
        strokes = strokes.map { s in
            guard selectedStrokeIds.contains(s.id) else { return s }
            return Stroke(id: s.id, points: s.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) },
                          color: s.color, lineWidth: s.lineWidth, isEraser: s.isEraser, isHighlighter: s.isHighlighter)
        }
        fillRegions = fillRegions.map { r in
            guard selectedFillIds.contains(r.id) else { return r }
            var t = CGAffineTransform(translationX: offset.width, y: offset.height)
            let newPath = r.path.copy(using: &t) ?? r.path
            return FillRegion(id: r.id, path: newPath, color: r.color)
        }
        if !selectionBoundary.isEmpty {
            selectionBoundary = selectionBoundary.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }

    // MARK: - Delete Selected

    private func pointSegDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq != 0 else { return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let px = a.x + t * dx, py = a.y + t * dy
        return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py))
    }

    // MARK: - RDP simplification

    func simplified(_ points: [CGPoint]) -> [CGPoint] {
        guard penSettings.smoothness > 1 else { return points }
        let result = simplify(points, epsilon: penSettings.smoothness)
        return result.count >= 2 ? result : points
    }

    private func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var dmax: CGFloat = 0
        var idx = 0
        for i in 1..<points.count - 1 {
            let d = perpDist(points[i], points[0], points[points.count - 1])
            if d > dmax { dmax = d; idx = i }
        }
        if dmax > epsilon {
            return simplify(Array(points[0...idx]), epsilon: epsilon).dropLast()
                + simplify(Array(points[idx..<points.count]), epsilon: epsilon)
        }
        return [points[0], points[points.count - 1]]
    }

    private func perpDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq != 0 else { return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let px = a.x + t * dx, py = a.y + t * dy
        return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py))
    }

    func deleteSelected() {
        guard !selectedStrokeIds.isEmpty || !selectedFillIds.isEmpty else {
            clear()
            return
        }
        saveState()
        strokes = strokes.filter { !selectedStrokeIds.contains($0.id) }
        fillRegions = fillRegions.filter { !selectedFillIds.contains($0.id) }
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
    }

    // MARK: - Eraser

    private func erase(_ eraser: Stroke) {
        let threshold = eraser.lineWidth / 2 + 2

        let hitByEraser: (Stroke) -> Bool = { pen in
            pen.points.contains { pp in
                eraser.points.contains { ep in
                    let dx = pp.x - ep.x, dy = pp.y - ep.y
                    return sqrt(dx * dx + dy * dy) < threshold
                }
            }
        }

        if eraserSettings.mode == .full {
            strokes = strokes.filter { $0.isEraser || !hitByEraser($0) }
        } else {
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
                            newStrokes.append(Stroke(points: segment, color: pen.color, lineWidth: pen.lineWidth, isEraser: false, isHighlighter: pen.isHighlighter))
                        }
                        segment = []
                    } else {
                        segment.append(pp)
                    }
                }
                if segment.count >= 2 {
                    newStrokes.append(Stroke(points: segment, color: pen.color, lineWidth: pen.lineWidth, isEraser: false, isHighlighter: pen.isHighlighter))
                }
            }
            strokes = newStrokes
        }

        fillRegions = fillRegions.filter { region in
            for ep in eraser.points {
                if region.path.contains(ep) { return false }
            }
            return true
        }
    }

    // MARK: - Fill

    func performFill(at canvasPoint: CGPoint) {
        saveState()
        guard let path = FloodFill.fillPath(at: canvasPoint, strokes: strokes) else {
            updateUndoRedo()
            return
        }
        let region = FillRegion(path: path, color: fillSettings.color.opacity(fillSettings.opacity))
        fillRegions.append(region)
        updateUndoRedo()
    }

    func selectTool(_ tool: Tool) {
        currentTool = tool
        if tool != .select {
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectionBoundary.removeAll()
        }
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds))
        let prev = undoStack.removeLast()
        strokes = prev.strokes
        fillRegions = prev.fillRegions
        selectedStrokeIds = prev.selectedStrokeIds
        selectedFillIds = prev.selectedFillIds
        updateUndoRedo()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds))
        let next = redoStack.removeLast()
        strokes = next.strokes
        fillRegions = next.fillRegions
        selectedStrokeIds = next.selectedStrokeIds
        selectedFillIds = next.selectedFillIds
        updateUndoRedo()
    }

    func clear() {
        saveState()
        strokes.removeAll()
        fillRegions.removeAll()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectionLasso.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
    }
}
