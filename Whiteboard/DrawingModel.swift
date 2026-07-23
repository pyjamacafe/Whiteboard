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

class DrawingModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var fillRegions: [FillRegion] = []
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

    func performFill(at canvasPoint: CGPoint) {
        guard let path = FloodFill.fillPath(at: canvasPoint, strokes: strokes) else { return }
        let region = FillRegion(path: path, color: Color.red.opacity(0.2))
        fillRegions.append(region)
    }

    func selectTool(_ tool: Tool) {
        currentTool = tool
    }

    func undo() {
        if !fillRegions.isEmpty {
            fillRegions.removeLast()
        } else {
            guard !strokes.isEmpty else { return }
            strokes.removeLast()
        }
    }

    func clear() {
        strokes.removeAll()
        fillRegions.removeAll()
        currentStroke = nil
    }
}
