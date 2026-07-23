import Combine
import SwiftUI

struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    let color: Color
    let lineWidth: CGFloat
    let isEraser: Bool
}

enum Tool {
    case pen, eraser
}

class DrawingModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var currentTool: Tool = .pen

    var currentStroke: Stroke?

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
        if let stroke = currentStroke, stroke.points.count >= 2 {
            strokes.append(stroke)
        }
        currentStroke = nil
    }

    func selectTool(_ tool: Tool) {
        currentTool = tool
    }

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    func clear() {
        strokes.removeAll()
        currentStroke = nil
    }
}
