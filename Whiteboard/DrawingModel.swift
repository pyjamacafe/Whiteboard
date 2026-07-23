import Combine
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct Stroke: Identifiable, Codable {
    var id = UUID()
    var points: [CGPoint]
    let color: CodableColor
    let lineWidth: CGFloat
    let isEraser: Bool
    let isHighlighter: Bool

    init(id: UUID = UUID(), points: [CGPoint], color: Color, lineWidth: CGFloat, isEraser: Bool, isHighlighter: Bool) {
        self.id = id
        self.points = points
        self.color = CodableColor(color)
        self.lineWidth = lineWidth
        self.isEraser = isEraser
        self.isHighlighter = isHighlighter
    }

    var uiColor: Color { color.color }
}

struct CodableColor: Codable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(_ color: Color) {
        #if os(iOS)
        let c = UIColor(color)
        #else
        let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(iOS)
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        self.r = Double(r); self.g = Double(g); self.b = Double(b); self.a = Double(a)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

struct FillRegion: Identifiable, Codable {
    var id = UUID()
    let path: CodablePath
    let color: CodableColor

    init(id: UUID = UUID(), path: CGPath, color: Color) {
        self.id = id
        self.path = CodablePath(path)
        self.color = CodableColor(color)
    }

    var uiColor: Color { color.color }
    var cgPath: CGPath { path.cgPath }
}

struct CodablePath: Codable {
    let points: [CodablePoint]

    init(_ path: CGPath) {
        var pts: [CodablePoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: pts.append(CodablePoint(e.points[0]))
            case .addLineToPoint: pts.append(CodablePoint(e.points[0]))
            case .addQuadCurveToPoint: pts.append(CodablePoint(e.points[0])); pts.append(CodablePoint(e.points[1]))
            case .addCurveToPoint: pts.append(CodablePoint(e.points[0])); pts.append(CodablePoint(e.points[1])); pts.append(CodablePoint(e.points[2]))
            case .closeSubpath: break
            @unknown default: break
            }
        }
        self.points = pts
    }

    var cgPath: CGPath {
        let raw = points.map(\.cgPoint)
        guard raw.count >= 2 else { return CGMutablePath() }
        let path = CGMutablePath()
        path.move(to: raw[0])
        for i in 1..<raw.count {
            path.addLine(to: raw[i])
        }
        path.closeSubpath()
        return path
    }
}

struct CodablePoint: Codable {
    let x: Double
    let y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

enum Tool: String, CaseIterable {
    case pen, eraser, fill, select, highlighter
}

enum CanvasBackground: String, CaseIterable {
    case none, grid, dots, ruled
}

struct AppSettings {
    var canvasBackground: CanvasBackground = .grid
    var isDarkMode: Bool = false
}

struct PenSettings {
    var lightColor: Color = .black
    var darkColor: Color = .white
    var thickness: CGFloat = 2
    var smoothness: CGFloat = 1
    var lightPresets: [Color] = [.black, .red, .orange, .yellow, .green, .blue, .purple, .brown]
    var darkPresets: [Color] = [.white, .red, .orange, .yellow, .green, .cyan, .purple, .pink]
}

struct FillSettings {
    var lightColor: Color = .red
    var darkColor: Color = .red
    var opacity: Double = 0.1
    var lightPresets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint]
    var darkPresets: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple, .pink, .mint]
}

enum EraserMode: String, CaseIterable {
    case partial = "Partial"
    case full = "Full Stroke"
}

struct EraserSettings {
    var mode: EraserMode = .partial
    var size: CGFloat = 20
}

struct HighlighterSettings {
    var lightColor: Color = .yellow
    var darkColor: Color = .yellow
    var thickness: CGFloat = 15
    var opacity: Double = 0.3
    var lightPresets: [Color] = [.yellow, .green, .cyan, .orange, .pink, .purple, .red, .blue]
    var darkPresets: [Color] = [.yellow, .green, .cyan, .orange, .pink, .purple, .red, .blue]
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
    @Published var appSettings = AppSettings()
    var openFileURL: URL?

    // Theme-aware colors
    var penColor: Color { appSettings.isDarkMode ? penSettings.darkColor : penSettings.lightColor }
    var penPresets: [Color] { appSettings.isDarkMode ? penSettings.darkPresets : penSettings.lightPresets }
    var fillColor: Color { appSettings.isDarkMode ? fillSettings.darkColor : fillSettings.lightColor }
    var fillPresets: [Color] { appSettings.isDarkMode ? fillSettings.darkPresets : fillSettings.lightPresets }
    var hlColor: Color { appSettings.isDarkMode ? highlighterSettings.darkColor : highlighterSettings.lightColor }
    var hlPresets: [Color] { appSettings.isDarkMode ? highlighterSettings.darkPresets : highlighterSettings.lightPresets }
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
            color: isEraser ? .white : isHighlight ? hlColor : penColor,
            lineWidth: isEraser ? eraserSettings.size : isHighlight ? highlighterSettings.thickness : penSettings.thickness,
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
            return
        } else if stroke.points.count >= 2 {
            var finalStroke = stroke
            if penSettings.smoothness > 1 && !stroke.isEraser && stroke.lineWidth < 10 {
                let simplified = simplify(stroke.points, epsilon: penSettings.smoothness)
                if simplified.count >= 2 {
                    finalStroke = Stroke(id: stroke.id, points: simplified, color: stroke.uiColor, lineWidth: stroke.lineWidth, isEraser: false, isHighlighter: stroke.isHighlighter)
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
            let box = region.cgPath.boundingBox
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
            if r.cgPath.contains(point) { return true }
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
                           color: s.uiColor, lineWidth: s.lineWidth, isEraser: s.isEraser, isHighlighter: s.isHighlighter)
        }
        fillRegions = fillRegions.map { r in
            guard selectedFillIds.contains(r.id) else { return r }
            var t = CGAffineTransform(translationX: offset.width, y: offset.height)
            let newPath = r.cgPath.copy(using: &t) ?? r.cgPath
            return FillRegion(id: r.id, path: newPath, color: r.uiColor)
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
        let threshold = eraser.lineWidth / 2
        let oldStrokes = strokes
        let oldFills = fillRegions

        let hitByEraser: (Stroke) -> Bool = { pen in
            pen.points.contains { pp in
                eraser.points.contains { ep in
                    let dx = pp.x - ep.x, dy = pp.y - ep.y
                    return sqrt(dx * dx + dy * dy) < threshold
                }
            }
        }

        DispatchQueue.main.async {
            if self.eraserSettings.mode == .full {
                self.strokes = oldStrokes.filter { $0.isEraser || !hitByEraser($0) }
            } else {
                var newStrokes: [Stroke] = []
                for pen in oldStrokes where !pen.isEraser {
                    var segment: [CGPoint] = []
                    for pp in pen.points {
                        let isErased = eraser.points.contains { ep in
                            let dx = pp.x - ep.x, dy = pp.y - ep.y
                            return sqrt(dx * dx + dy * dy) < threshold
                        }
                        if isErased {
                            if segment.count >= 2 {
                                newStrokes.append(Stroke(points: segment, color: pen.uiColor, lineWidth: pen.lineWidth, isEraser: false, isHighlighter: pen.isHighlighter))
                        }
                        segment = []
                    } else {
                        segment.append(pp)
                    }
                }
                if segment.count >= 2 {
                        newStrokes.append(Stroke(points: segment, color: pen.uiColor, lineWidth: pen.lineWidth, isEraser: false, isHighlighter: pen.isHighlighter))
                    }
                }
                self.strokes = newStrokes
            }

            self.fillRegions = oldFills.filter { region in
                for ep in eraser.points {
                    if region.cgPath.contains(ep) { return false }
                }
                return true
            }
            self.updateUndoRedo()
        }
    }

    // MARK: - Fill

    func performFill(at canvasPoint: CGPoint) {
        saveState()
        guard let path = FloodFill.fillPath(at: canvasPoint, strokes: strokes) else {
            updateUndoRedo()
            return
        }
        let region = FillRegion(path: path, color: fillColor.opacity(fillSettings.opacity))
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
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoRedo()
    }

    // MARK: - Save / Load / Export

    private struct SaveData: Codable {
        let strokes: [Stroke]
        let fillRegions: [FillRegion]
    }

    func saveData() -> Data? {
        let data = SaveData(strokes: strokes, fillRegions: fillRegions)
        return try? JSONEncoder().encode(data)
    }

    func loadData(_ data: Data) {
        guard let save = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        saveState()
        strokes = save.strokes
        fillRegions = save.fillRegions
        updateUndoRedo()
    }

    func save() {
        guard let url = openFileURL else { return }
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
        if let data = saveData() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Menu command helpers (triggered by menu bar or keyboard)

    func openCmd() { pendingAction = .open }
    func exportPNG() { pendingAction = .export(.png) }
    func exportPDF() { pendingAction = .export(.pdf) }

    enum PendingAction: Equatable {
        case open
        case export(ExportFormat)
    }

    enum ExportFormat: String { case png, pdf }
    @Published var pendingAction: PendingAction?
    @Published var isToolbarVisible: Bool = true

    func pngData(size: CGSize, offset: CGPoint = .zero, scale: CGFloat = 3) -> Data? {
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard w > 0, h > 0, w <= 8192, h <= 8192 else { return nil }

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: -offset.x * scale, y: -offset.y * scale)
        ctx.scaleBy(x: scale, y: scale)

        // Render fills
        for r in fillRegions {
            ctx.setFillColor(r.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.beginPath()
            ctx.addPath(r.cgPath)
            ctx.fillPath()
        }

        // Render strokes (highlighter first)
        for s in strokes where s.isHighlighter {
            renderStrokeForExport(s, ctx: ctx)
        }
        for s in strokes where !s.isHighlighter {
            renderStrokeForExport(s, ctx: ctx)
        }

        guard let image = ctx.makeImage() else { return nil }
        let cfData = CFDataCreateMutable(nil, 0)
        guard let dest = CGImageDestinationCreateWithData(cfData!, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return cfData! as Data
    }

    private func renderStrokeForExport(_ s: Stroke, ctx: CGContext) {
        guard s.points.count >= 2 else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if s.isEraser {
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(s.lineWidth)
        } else {
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(s.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(s.lineWidth)
        }
        ctx.addLines(between: s.points)
        ctx.strokePath()
        ctx.restoreGState()
    }

    func pdfData(size: CGSize, offset: CGPoint = .zero) -> Data? {
        let rect = CGRect(origin: .zero, size: size)
        let cfData = CFDataCreateMutable(nil, 0)
        guard let consumer = CGDataConsumer(data: cfData!) else { return nil }
        var mediaBox = rect
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        pdf.beginPDFPage(nil)
        pdf.translateBy(x: -offset.x, y: -offset.y)
        renderToContext(pdf, size: size)
        pdf.endPDFPage()
        pdf.closePDF()
        return cfData! as Data
    }

    private func renderToContext(_ ctx: CGContext, size: CGSize) {
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))

        for r in fillRegions {
            ctx.setFillColor(r.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.beginPath()
            ctx.addPath(r.cgPath)
            ctx.fillPath()
        }
        for s in strokes where s.isHighlighter {
            renderStrokeForExport(s, ctx: ctx)
        }
        for s in strokes where !s.isHighlighter {
            renderStrokeForExport(s, ctx: ctx)
        }
    }
}
